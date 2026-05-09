output "replication_role_arn" {
  description = "ARN of the IAM role used for S3 log replication."
  value       = aws_iam_role.replication.arn
}

output "replication_role_name" {
  description = "Name of the IAM role used for S3 log replication."
  value       = aws_iam_role.replication.name
}
