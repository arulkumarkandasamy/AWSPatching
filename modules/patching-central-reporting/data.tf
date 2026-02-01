# Helper data source to get current account ID for the policy above
data "aws_caller_identity" "current" {}

# Get Organization Details
data "aws_organizations_organization" "org" {}

# Find AMI for Windows Server 2022
data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
}