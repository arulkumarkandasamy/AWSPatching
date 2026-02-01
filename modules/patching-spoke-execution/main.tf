terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}


# 1. Resource Data Sync (Points to Central Reporting Bucket)
resource "aws_ssm_resource_data_sync" "central_sync" {
  name = "CCS-Org-Patch-Sync"
  s3_destination {
    bucket_name = var.central_bucket_name
    region      = var.central_bucket_region
    sync_format = "JsonSerDe"
  }
}

# 3. Maintenance Window
resource "aws_ssm_maintenance_window" "patching_window" {
  name     = "CCS-${var.patch_tag_value}-Window"
  schedule = var.schedule_cron
  duration = 3
  cutoff   = 1
  allow_unassociated_targets = true
}

# 4. Target Selection (With Opt-Out Capability)
# Strategy: We target a specific tag. To Opt-out, owners simply remove this tag.
resource "aws_ssm_maintenance_window_target" "target_instances" {
  window_id     = aws_ssm_maintenance_window.patching_window.id
  resource_type = "INSTANCE"

  targets {
    key    = "tag:${var.patch_tag_key}"
    values = [var.patch_tag_value]
  }
}

# 5. Register the Custom Orchestrator Task
resource "aws_ssm_maintenance_window_task" "patch_task" {
  window_id        = aws_ssm_maintenance_window.patching_window.id
  task_type        = "AUTOMATION"
  task_arn         = aws_ssm_document.orchestrator.name
  priority         = 1
  service_role_arn = aws_iam_role.mw_service_role.arn
  max_concurrency  = "10"
  max_errors       = "1"

  name        = "CCS-Patching-Task-${var.patch_tag_value}"
  description = "Orchestrated Patching for ${var.patch_tag_value}"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.target_instances.id]
  }

  task_invocation_parameters {
    automation_parameters {
      # FIX: Use {{RESOURCE_ID}} and ensure no extra text artifacts exist
      parameter {
        name   = "InstanceId"
        values = ["{{RESOURCE_ID}}"]
      }
      parameter {
        name   = "AutomationAssumeRole"
        values = [aws_iam_role.mw_service_role.arn]
      }
      # Optional
      parameter {
        name   = "Operation"
        values = ["Install"]
      }
    }
  }
}

# 6. Notification (SNS)
resource "aws_sns_topic" "patch_alerts" {
  name = "CCS-Patching-Alerts"
}

# Note: SSM natively supports sending notifications to SNS on task failure
# but since we are using an Automation Task, we handle failure alerts via 
# CloudWatch Events or simply subscribing to the task status.
# Below adds a subscription for stakeholders.
resource "aws_sns_topic_subscription" "email_target" {
  topic_arn = aws_sns_topic.patch_alerts.arn
  protocol  = "email"
  endpoint  = var.stakeholder_email
}


# --- TRIGGER LOGIC ---

# 1. EventBridge Rule: Catches "Automation Finished" for our specific document
resource "aws_cloudwatch_event_rule" "patch_completion" {
  name        = "CCS-Patch-Completion-Rule"
  description = "Trigger Instant Report when Patching Automation finishes"

  event_pattern = jsonencode({
    source      = ["aws.ssm"],
    detail-type = ["SSM Automation Execution State-change"],
    detail = {
      Status       = ["Success", "Failed"],
      DocumentName = [aws_ssm_document.orchestrator.name] 
    }
  })
}

# 2. EventBridge Target: SNS Topic
# We use an Input Transformer to format the JSON exactly how the Lambda expects it
resource "aws_cloudwatch_event_target" "sns_trigger" {
  rule      = aws_cloudwatch_event_rule.patch_completion.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.patch_alerts.arn

  input_transformer {
    input_paths = {
      instanceId = "$.detail.Target"
      status     = "$.detail.Status"
    }
    # This formats the message sent to SNS as: {"instanceId": "i-12345", "status": "Success"}
    input_template = "{\"instanceId\": <instanceId>, \"status\": <status>}"
  }
}

# --- NEW: DAILY COMPLIANCE SCAN (The "Patch Policy") ---
# This runs "Scan" operation daily. It does NOT install patches or reboot.
# It ensures your Compliance Dashboard is always up to date.

resource "aws_ssm_association" "daily_compliance_scan" {
  ### name             = "CCS-Daily-Patch-Compliance-Scan"
  association_name = "CCS-Daily-Patch-Compliance-Scan"
  
  # Uses the standard AWS Document. It automatically finds the correct Baseline 
  # based on the "Patch Group" we configured earlier.
  name = "AWS-RunPatchBaseline"

  # Run Daily at 1 AM (Different time from maintenance window to avoid conflicts)
  schedule_expression = "cron(0 1 * * ? *)" 

  # Target the same instances as your Patching Window
  targets {
    key    = "tag:${var.patch_tag_key}"
    values = [var.patch_tag_value]
  }

  # FORCE SCAN ONLY (No Reboots)
  parameters = {
    Operation = "Scan"
  }
  
  # Send output to S3 so we can debug if scanning fails
  output_location {
    s3_bucket_name = var.central_bucket_name
    s3_key_prefix  = "logs/compliance-scan"
  }

  # Clean up automation history to keep console tidy
  max_concurrency = "10"
  max_errors      = "1"
}


# --- NEW: Notification Rule for Automation Status ---
resource "aws_cloudwatch_event_rule" "patch_status_monitor" {
  name        = "CCS-Patch-Status-Monitor-${var.patch_tag_value}"
  description = "Triggers notifications based on Patching Automation status (Success, Failed, etc.)"

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["SSM Automation Execution State Change"]
    detail = {
      # Watch ONLY our Orchestrator document
      Definition = [aws_ssm_document.orchestrator.name]
      # Filter by the statuses defined in your variable (e.g. Success, Failed, TimedOut)
      Status     = var.patching_task_notification_events 
    }
  })
}

# --- NEW: Notification Rule for Automation Status ---
resource "aws_cloudwatch_event_target" "sns_status_alert" {
  rule      = aws_cloudwatch_event_rule.patch_status_monitor.name
  target_id = "SendPatchStatusEmail"
  arn       = aws_sns_topic.patch_alerts.arn
  
  input_transformer {
    input_paths = {
      status = "$.detail.Status"
      doc    = "$.detail.Definition"
      time   = "$.time"
      execId = "$.detail.ExecutionId"
    }
    
    # FIX: Formatted as a valid JSON object to satisfy EventBridge validation.
    input_template = <<EOF
{
  "Summary": "Patching Task Update",
  "Status": "<status>",
  "Document": "<doc>",
  "Time": "<time>",
  "ExecutionID": "<execId>",
  "Action": "Check the AWS Console for full details."
}
EOF
  }
}