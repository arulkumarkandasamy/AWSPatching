# [file: lambda.tf]

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    filename = "lambda_instant_patching_report.py"
    content  = <<EOF
from __future__ import print_function
import json
import boto3
import os

ses = boto3.client('ses')
OWNER_MAP = json.loads(os.environ['OWNER_MAP'])
SENDER_EMAIL = os.environ['SENDER_EMAIL']

def send_email(to_email, subject, body):
    try:
        ses.send_email(
            Source=SENDER_EMAIL,
            Destination={'ToAddresses': [to_email]},
            Message={
                'Subject': {'Data': subject},
                'Body': {'Text': {'Data': body}}
            }
        )
        print(f"Email sent to {to_email}")
    except Exception as e:
        print(f"SES Error: {e}")

def lambda_handler(event, context):
    accountId = context.invoked_function_arn.split(":")[4]
    
    # 1. Parse EventBridge->SNS Payload
    try:
        sns_message = event['Records'][0]['Sns']['Message']
        payload = json.loads(sns_message)
        instanceid = payload.get('instanceId')
        status = payload.get('status', 'Unknown')
    except Exception as e:
        print(f"Error parsing event: {e}")
        return

    if not instanceid: return

    # 2. Lookup Owner
    owner_email = OWNER_MAP.get(instanceid)
    if not owner_email:
        print(f"No owner found for {instanceid}. Skipping email.")
        return

    # 3. Construct Message
    subject = f"Patching {status}: Instance {instanceid}"
    message = f"""
    Patching Automation Status Update:
    
    Instance ID: {instanceid}
    Account ID:  {accountId}
    Status:      {status}
    
    Please check the AWS Systems Manager console for detailed logs.
    """

    # 4. Send Email
    print(f"Sending {status} alert to {owner_email}")
    send_email(owner_email, subject, message)
    
    # Optional: If status is Failed, we can still perform compliance checks here if needed
    # (Previous compliance logic removed for brevity, add back if strict compliance report needed)
    return status
EOF
  }
}

resource "aws_lambda_function" "instant_report" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "CCS-Instant-Patch-Report"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_instant_patching_report.lambda_handler"
  runtime          = "python3.9"
  timeout          = 60
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      OWNER_MAP    = jsonencode(local.instance_owner_map)
      SENDER_EMAIL = var.stakeholder_email
    }
  }
}