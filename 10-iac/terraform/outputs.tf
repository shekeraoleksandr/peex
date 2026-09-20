output "bucket_name" {
  description = "Name of the provisioned bucket"
  value       = aws_s3_bucket.iac_demo.bucket
}

output "bucket_arn" {
  description = "ARN of the provisioned bucket"
  value       = aws_s3_bucket.iac_demo.arn
}

output "versioning_status" {
  description = "Current versioning status"
  value       = aws_s3_bucket_versioning.iac_demo.versioning_configuration[0].status
}
