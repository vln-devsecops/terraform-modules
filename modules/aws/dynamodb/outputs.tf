output "table_arn" {
  description = "ARN of the DynamoDB table."
  value       = aws_dynamodb_table.this.arn
}

output "table_name" {
  description = "Name of the DynamoDB table."
  value       = aws_dynamodb_table.this.name
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for DynamoDB encryption."
  value       = local.kms_key_arn
}
