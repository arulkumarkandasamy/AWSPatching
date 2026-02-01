# =============================================================================
# 1. DYNAMODB TABLES (RESTORED)
# =============================================================================

# Table 1: Opt-Out State
resource "aws_dynamodb_table" "opt_out_state" {
  # Added variable suffix to prevent Dev/Prod collision
  name           = "CCS-Patching-OptOut-State-${var.patch_tag_value}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "AccountId"

  attribute {
    name = "AccountId"
    type = "S"
  }
}

# Table 2: Notification History (Prevents duplicate emails)
resource "aws_dynamodb_table" "notification_history" {
  name           = "CCS-Patching-Notify-History-${var.patch_tag_value}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "WindowId"
  range_key      = "AlertKey" 

  attribute {
    name = "WindowId"
    type = "S"
  }
  attribute {
    name = "AlertKey"
    type = "S"
  }
  
  ttl {
    attribute_name = "Expiry"
    enabled        = true
  }
}

# =============================================================================
# 2. API GATEWAY (RESTORED)
# =============================================================================

resource "aws_apigatewayv2_api" "opt_out_api" {
  name          = "CCS-Patching-OptOut-API-${var.patch_tag_value}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.opt_out_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.opt_out_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.opt_out_handler.invoke_arn
}

resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.opt_out_api.id
  route_key = "GET /opt-out"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# =============================================================================
# 3. IAM ROLES (RESTORED & UPDATED)
# =============================================================================

resource "aws_iam_role" "lambda_opt_out_role" {
  name = "CCS-Patching-OptOut-Role-${var.patch_tag_value}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "lambda_opt_out_policy" {
  role = aws_iam_role.lambda_opt_out_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # DynamoDB Access
      {
        Effect = "Allow",
        Action = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem"],
        Resource = [
          aws_dynamodb_table.opt_out_state.arn,
          aws_dynamodb_table.notification_history.arn
        ]
      },
      # SNS Publish (Legacy) + SES Send (New)
      {
        Effect = "Allow",
        Action = ["sns:Publish", "ses:SendEmail", "ses:SendRawEmail"],
        Resource = "*"
      },
      # SSM & EC2 Access (For Polling and Tag Lookup)
      {
        Effect = "Allow",
        Action = [
          "ssm:DescribeMaintenanceWindows", 
          "ssm:GetMaintenanceWindow",
          "ec2:DescribeInstances" 
        ],
        Resource = "*"
      },
      # Logs
      {
        Effect = "Allow",
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# =============================================================================
# 4. LAMBDA: OPT-OUT HANDLER (The "Click" Handler)
# =============================================================================

data "archive_file" "opt_out_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/opt_out_lambda.zip"
  source {
    filename = "handler.py"
    content  = <<EOF
import boto3
import os
import time

dynamodb = boto3.resource('dynamodb')
table_name = os.environ['TABLE_NAME']
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    try:
        query_params = event.get('queryStringParameters') or {}
        account_id = query_params.get('accountId')
        if not account_id:
            return {"statusCode": 400, "body": "Missing AccountId"}

        # Set Opt-Out to expire in 7 days
        expiry = int(time.time()) + (7 * 24 * 60 * 60)
        
        table.put_item(
            Item={
                'AccountId': account_id,
                'OptOutExpiry': expiry,
                'Status': 'Opted-Out'
            }
        )
        
        html = """
        <html>
        <body style="font-family: sans-serif; text-align: center; padding: 50px;">
            <h1 style="color: green;">Opt-Out Successful</h1>
            <p>Patching for Account <b>{}</b> has been postponed to the next cycle.</p>
        </body>
        </html>
        """.format(account_id)

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "text/html"},
            "body": html
        }
    except Exception as e:
        print(e)
        return {"statusCode": 500, "body": "Error processing request"}
EOF
  }
}

resource "aws_lambda_function" "opt_out_handler" {
  filename         = data.archive_file.opt_out_lambda_zip.output_path
  function_name    = "CCS-Patching-OptOut-Handler-${var.patch_tag_value}"
  role             = aws_iam_role.lambda_opt_out_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.opt_out_lambda_zip.output_base64sha256
  environment {
    variables = { TABLE_NAME = aws_dynamodb_table.opt_out_state.name }
  }
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.opt_out_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.opt_out_api.execution_arn}/*/*"
}

# =============================================================================
# 5. LAMBDA: NOTIFIER (UPDATED with Owner Map Logic)
# =============================================================================

data "archive_file" "notify_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/notify_lambda.zip"
  
  source {
    filename = "notify.py"
    content  = <<EOF
import boto3
import os
import time
import json
import dateutil.parser
from datetime import datetime, timezone

ses = boto3.client('ses')
ssm = boto3.client('ssm')
ec2 = boto3.client('ec2')
dynamodb = boto3.resource('dynamodb')

API_URL       = os.environ['API_URL']
HISTORY_TABLE = os.environ['HISTORY_TABLE']
OWNER_MAP     = json.loads(os.environ['OWNER_MAP'])
PATCH_TAG     = os.environ['PATCH_TAG_VALUE']
SENDER_EMAIL  = os.environ['SENDER_EMAIL']

hist_table = dynamodb.Table(HISTORY_TABLE)

def lambda_handler(event, context):
    print("Starting Maintenance Window Poll...")
    paginator = ssm.get_paginator('describe_maintenance_windows')
    for page in paginator.paginate():
        for window in page['WindowIdentities']:
            check_window(window)

def check_window(window):
    window_id = window['WindowId']
    name = window['Name']
    
    # Filter for our specific windows (CCS-Dev or CCS-Prod)
    if "CCS" not in name: return

    try:
        details = ssm.get_maintenance_window(WindowId=window_id)
        next_exec_str = details['NextExecutionTime']
        next_exec_dt = dateutil.parser.parse(next_exec_str)
        now_dt = datetime.now(timezone.utc)
        diff = next_exec_dt - now_dt
        hours_remaining = diff.total_seconds() / 3600
        
        # Check alerts: 7 Days (approx) or 1 Day (approx)
        alert_type = None
        if 166 <= hours_remaining <= 169:
            alert_type = "7Day"
        elif 23 <= hours_remaining <= 25:
            alert_type = "1Day"
            
        if alert_type:
            send_targeted_notifications(window_id, name, next_exec_str, alert_type)
            
    except Exception as e:
        print(f"Error checking window {window_id}: {e}")

def get_target_instances():
    # Find all instances that belong to this Patch Group
    instances = []
    paginator = ec2.get_paginator('describe_instances')
    iterator = paginator.paginate(
        Filters=[{'Name': 'tag:PatchGroup', 'Values': [PATCH_TAG]}]
    )
    for page in iterator:
        for r in page['Reservations']:
            for i in r['Instances']:
                instances.append(i['InstanceId'])
    return instances

def send_targeted_notifications(window_id, window_name, execution_time, alert_type):
    # 1. Check Deduplication
    alert_key = f"{execution_time}#{alert_type}"
    try:
        resp = hist_table.get_item(Key={'WindowId': window_id, 'AlertKey': alert_key})
        if 'Item' in resp:
            print(f"Skipping {alert_type} - Already processed.")
            return
    except Exception as e:
        print(f"DB Error: {e}")

    # 2. Get Targets
    target_ids = get_target_instances()
    print(f"Found {len(target_ids)} instances in patch group {PATCH_TAG}")

    # 3. Iterate and Email Owners
    readable_type = alert_type.replace("Day", " Day")
    
    for instance_id in target_ids:
        owner_email = OWNER_MAP.get(instance_id)
        
        if owner_email:
            account_id = boto3.client('sts').get_caller_identity().get('Account')
            opt_out_link = f"{API_URL}/opt-out?accountId={account_id}"
            
            subject = f"ACTION REQUIRED: Patching for {instance_id} in {readable_type}"
            body = f"""
            Hello,
            
            Your instance {instance_id} is scheduled for patching.
            
            Window: {window_name}
            Time: {execution_time}
            
            If you need to defer this patch cycle, please click the link below:
            {opt_out_link}
            """
            
            try:
                ses.send_email(
                    Source=SENDER_EMAIL,
                    Destination={'ToAddresses': [owner_email]},
                    Message={
                        'Subject': {'Data': subject},
                        'Body': {'Text': {'Data': body}}
                    }
                )
                print(f"Sent email to {owner_email} for {instance_id}")
            except Exception as e:
                print(f"Failed to email {owner_email}: {e}")

    # 4. Update History
    ttl = int(time.time()) + (30 * 24 * 60 * 60)
    hist_table.put_item(
        Item={
            'WindowId': window_id,
            'AlertKey': alert_key,
            'SentAt': str(datetime.now()),
            'Expiry': ttl
        }
    )
EOF
  }
}

resource "aws_lambda_function" "notifier" {
  filename         = data.archive_file.notify_lambda_zip.output_path
  function_name    = "CCS-Patching-Notification-Poller-${var.patch_tag_value}"
  role             = aws_iam_role.lambda_opt_out_role.arn
  handler          = "notify.lambda_handler"
  runtime          = "python3.9"
  timeout          = 300 
  source_code_hash = data.archive_file.notify_lambda_zip.output_base64sha256

  environment {
    variables = {
      API_URL         = aws_apigatewayv2_api.opt_out_api.api_endpoint
      OPTOUT_TABLE    = aws_dynamodb_table.opt_out_state.name
      HISTORY_TABLE   = aws_dynamodb_table.notification_history.name
      OWNER_MAP       = jsonencode(local.instance_owner_map)
      PATCH_TAG_VALUE = var.patch_tag_value
      SENDER_EMAIL    = var.stakeholder_email
    }
  }
}

# 6. TRIGGER: HOURLY POLL
resource "aws_cloudwatch_event_rule" "hourly_poll" {
  name                = "CCS-Patching-Hourly-Poller-${var.patch_tag_value}"
  description         = "Polls Maintenance Windows every hour"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "poll_target" {
  rule      = aws_cloudwatch_event_rule.hourly_poll.name
  target_id = "PollMaintenanceWindows"
  arn       = aws_lambda_function.notifier.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notifier.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.hourly_poll.arn
}