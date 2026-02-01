variable "bucket_name" {
  description = "Unique name for the central compliance S3 bucket"
  type        = string
}

variable "org_id" {
  description = "AWS Organization ID (o-xxxxxx) to allow data syncing"
  type        = string
}