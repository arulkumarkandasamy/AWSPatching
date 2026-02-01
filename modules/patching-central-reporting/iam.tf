resource "aws_iam_role" "glue_service_role" {
  name = "AWSGlueServiceRole-Patching-Org"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "glue.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_svc" {
  role       = aws_iam_role.glue_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_access" {
  role = aws_iam_role.glue_service_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["s3:GetObject", "s3:PutObject"]
        Effect = "Allow"
        Resource = "arn:aws:s3:::${var.bucket_name}/*"
      }
    ]
  })
}

# Allow ALL accounts in the Org to push inventory data here
resource "aws_s3_bucket_policy" "compliance_policy" {
  bucket = aws_s3_bucket.compliance_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowOrgSSMPut"
        Effect    = "Allow"
        Principal = { Service = "ssm.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.compliance_bucket.arn}/*"
        Condition = {
          StringEquals = { "aws:SourceOrgID" = var.org_id }
        }
      },
      {
        Sid       = "AllowOrgBucketAcl"
        Effect    = "Allow"
        Principal = { Service = "ssm.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.compliance_bucket.arn
        Condition = {
          StringEquals = { "aws:SourceOrgID" = var.org_id }
        }
      },
      # (Optional) Allow your current account admin to manage the bucket
      {
        Sid       = "AllowRootAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "s3:*"
        Resource  = [
          "arn:aws:s3:::${var.bucket_name}",
          "arn:aws:s3:::${var.bucket_name}/*"
        ]
      }
    ]
  })
}

# IAM Role for WSUS
resource "aws_iam_role" "wsus_role" {
  name = "CCS-WSUS-Server-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy_attachment" "wsus_ssm" {
  role       = aws_iam_role.wsus_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "wsus_profile" {
  name = "CCS-WSUS-Profile"
  role = aws_iam_role.wsus_role.name
}