# --- MODULES ---

# 1. Central Reporting (Management Account)
module "central_reporting" {
  source = "./modules/patching-central-reporting"
  providers = { aws = aws.management }

  bucket_name = "ccs-org-patch-logs-mgmt-unique-123" 
  org_id      = var.org_id
}

# 2c. Prod Patching Logic
module "prod_patching" {
  source = "./modules/patching-spoke-execution"
  providers = { aws = aws.production }

  central_bucket_name   = module.central_reporting.bucket_name
  central_bucket_region = "us-east-1"
  patch_tag_value       = "Production"
  stakeholder_email     = var.stakeholder_email
}

# 3c. Dev Patching Logic
module "dev_patching" {
  source = "./modules/patching-spoke-execution"
  providers = { aws = aws.development }

  central_bucket_name   = module.central_reporting.bucket_name
  central_bucket_region = "us-east-1"
  patch_tag_value       = "Development"
  stakeholder_email     = var.stakeholder_email
}