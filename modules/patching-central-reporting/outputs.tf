# modules/patching-central-reporting/outputs.tf

output "bucket_name" {
  description = "The name of the S3 bucket created for central reporting"
  value       = aws_s3_bucket.compliance_bucket.id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = aws_s3_bucket.compliance_bucket.arn
}

# output "wsus_ip" {
#   value = aws_instance.wsus_server.private_ip
# }

output "tgw_id" {
  value = aws_ec2_transit_gateway.hub_tgw.id
  description = "The ID of the Hub Transit Gateway"
}