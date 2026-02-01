# --- MONTHLY CSV REPORTING (Legacy Export) ---

# 1. IAM Role for the Reporting Automation
# This role is assumed by the SSM Automation service to run the export logic.
resource "aws_iam_role" "csv_report_role" {
  name = "CCS-CSV-Report-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = { Service = "ssm.amazonaws.com" }
      }
    ]
  })
}

# 2. Permissions for the Reporting Role
# It needs to read inventory data and write the CSV to the S3 bucket.
resource "aws_iam_role_policy" "csv_report_policy" {
  name = "CCS-CSV-Report-Policy"
  role = aws_iam_role.csv_report_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Allow writing the CSV to the Central Bucket
      {
        Effect   = "Allow"
        Action   = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${var.central_bucket_name}",
          "arn:aws:s3:::${var.central_bucket_name}/*"
        ]
      },
      # Allow gathering Patch Compliance data
      {
        Effect = "Allow"
        Action = [
          "ssm:DescribeInstanceInformation",
          "ssm:ListComplianceItems",
          "ssm:ListResourceDataSync"
        ]
        Resource = "*"
      }
    ]
  })
}

# 3. CloudWatch Event Rule (The Schedule)
# Triggers at 06:00 UTC on the 1st day of every month
resource "aws_cloudwatch_event_rule" "monthly_report_schedule" {
  name                = "CCS-Monthly-Patch-Report-Trigger"
  description         = "Triggers generation of static CSV Patch Report on the 1st of every month"
  schedule_expression = "cron(0 6 1 * ? *)" 
}

# 4. CloudWatch Event Target (The Action)
# Triggers the AWS-ExportPatchReportToS3 automation
resource "aws_cloudwatch_event_target" "trigger_report_automation" {
  rule      = aws_cloudwatch_event_rule.monthly_report_schedule.name
  target_id = "GenerateCSVReport"
  arn       = "arn:aws:ssm:${data.aws_region.current.name}::automation-definition/AWS-ExportPatchReportToS3"
  role_arn  = aws_iam_role.event_bridge_invoke_role.arn # The role EventBridge uses to start SSM

  input = jsonencode({
    S3BucketName = var.central_bucket_name
    S3KeyPrefix  = "reports/monthly-csv"
    AutomationAssumeRole = aws_iam_role.csv_report_role.arn
  })
}

# 5. IAM Role for EventBridge (The Triggerer)
# EventBridge needs permission to "StartAutomationExecution"
resource "aws_iam_role" "event_bridge_invoke_role" {
  name = "CCS-EventBridge-Invoke-SSM-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = { Service = "events.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy" "event_bridge_invoke_policy" {
  name = "CCS-EventBridge-Invoke-SSM-Policy"
  role = aws_iam_role.event_bridge_invoke_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:StartAutomationExecution"
        Resource = "arn:aws:ssm:${data.aws_region.current.name}::automation-definition/AWS-ExportPatchReportToS3"
      },
      # PassRole is required so EventBridge can tell SSM to use the "csv_report_role"
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.csv_report_role.arn
        Condition = {
          StringLikeIfExists = {
            "iam:PassedToService": "ssm.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Helper to get current region dynamically
data "aws_region" "current" {}