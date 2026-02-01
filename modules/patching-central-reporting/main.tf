terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_s3_bucket" "compliance_bucket" {
  bucket        = var.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_encryption" {
  bucket = aws_s3_bucket.compliance_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Glue Components for Quicksight/Athena
resource "aws_glue_catalog_database" "patch_db" {
  name = "org_patch_compliance_db"
}

resource "aws_glue_crawler" "patch_crawler" {
  name          = "org-patch-compliance-crawler"
  database_name = aws_glue_catalog_database.patch_db.name
  role          = aws_iam_role.glue_service_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.compliance_bucket.bucket}"
  }
  
  schedule = "cron(0 10 * * ? *)" # Run daily at 10am
}

# Athena Query to Generate the CSV Report
resource "aws_athena_named_query" "compliance_report" {
  name      = "OrgPatchComplianceCSV"
  database  = aws_glue_catalog_database.patch_db.name
  query     = <<EOF
SELECT 
  accountid, 
  resourceid as instance_id, 
  "aws:instanceinformation.platformname" as os, 
  status as compliance_status,
  "aws:instanceinformation.computername" as hostname
FROM "${aws_glue_catalog_database.patch_db.name}"."${replace(var.bucket_name, "-", "_")}" 
WHERE status != 'COMPLIANT'
EOF
}