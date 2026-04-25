output "bucket_arn" {
  description = "ARN of the deployment bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_id" {
  description = "ID of the deployment bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_name" {
  description = "Name of the deployment bucket."
  value       = aws_s3_bucket.this.bucket
}
