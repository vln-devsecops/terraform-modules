output "bucket_name" {
  description = "Name of the central logs S3 bucket."
  value       = aws_s3_bucket.logs.id
}

output "bucket_arn" {
  description = "ARN of the central logs S3 bucket."
  value       = aws_s3_bucket.logs.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for bucket encryption, or null when create_kms_key is false."
  value       = var.create_kms_key ? aws_kms_key.logs[0].arn : null
}

output "kms_key_id" {
  description = "Key ID of the KMS key used for bucket encryption, or null when create_kms_key is false."
  value       = var.create_kms_key ? aws_kms_key.logs[0].id : null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail, or null when enable_cloudtrail is false."
  value       = var.enable_cloudtrail ? aws_cloudtrail.central[0].arn : null
}
