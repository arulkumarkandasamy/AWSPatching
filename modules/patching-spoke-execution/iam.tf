resource "aws_iam_role" "mw_service_role" {
  name = "CCS-Patching-MW-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ssm.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_automation" {
  role       = aws_iam_role.mw_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSSMAutomationRole"
}

resource "aws_iam_role_policy" "mw_service_role_policy" {
  name = "CCS-Patching-MW-Service-Policy"
  role = aws_iam_role.mw_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # 1. Existing Permissions (SSM, EC2, Logs)
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:CancelCommand",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ssm:GetCommandInvocation",
          "ssm:GetAutomationExecution",
          "ssm:StartAutomationExecution",
          "ssm:ListTagsForResource",
          "ssm:GetParameters"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeTags",
          "ec2:CreateSnapshot",       # Needed for the Snapshot step
          "ec2:CreateTags",           # Needed for tagging Snapshots
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes",
          "ec2:MonitorInstances",    # Needed To Enable Alarms
          "ec2:UnmonitorInstances"   # Needed To Disable Alarms
        ]
        Resource = "*"
      },
      # 2. Existing ASG Permissions (for Standby Step)
      {
        Effect = "Allow",
        Action = [
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:EnterStandby",
          "autoscaling:ExitStandby"
        ],
        Resource = "*"
      },
      # 3. Existing SNS Permissions (for Email Notifications)
      {
        Effect = "Allow",
        Action = "sns:Publish",
        Resource = aws_sns_topic.patch_alerts.arn
      },
      # 4. NEW FIX: Allow Reading Opt-Out Status from DynamoDB
      {
        Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan" 
        ],
        Resource = aws_dynamodb_table.opt_out_state.arn
      },
      # 5. Pass Role (Required for Automation to assume itself or other roles)
      {
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = aws_iam_role.mw_service_role.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "invoke_commands" {
  role = aws_iam_role.mw_service_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = ["ssm:SendCommand", "ssm:StartAutomationExecution", "ssm:GetAutomationExecution", "ssm:ListCommandInvocations"],
        Resource = "*"
      },
      {
        Sid    = "AllowPassingRoleToSSM"
        Effect = "Allow",
        Action = "iam:PassRole",
        Resource = aws_iam_role.mw_service_role.arn,

        # Security Best Practice: Only allow passing to SSM
        Condition = {
            StringLikeIfExists = {
                "iam:PassedToService": "ssm.amazonaws.com"
            }
        }
      }
    ]
  })
}

# ... (Previous roles for EC2/MW remain) ...

# NEW: Role for the Reporting Lambda
resource "aws_iam_role" "lambda_role" {
  name = "CCS-Patching-Lambda-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Logging
      {
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      # Read Compliance Data
      {
        Action   = ["ssm:ListComplianceItems", "ssm:DescribeInstanceInformation"]
        Effect   = "Allow"
        Resource = "*"
      },
      # Publish Alerts to SNS
      {
        Action   = "sns:Publish"
        Effect   = "Allow"
        Resource = aws_sns_topic.patch_alerts.arn
      },
      # Allow sending targeted emails via SES
      {
        Effect = "Allow"
        Action = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*" 
      }
      
    ]
  })
}
