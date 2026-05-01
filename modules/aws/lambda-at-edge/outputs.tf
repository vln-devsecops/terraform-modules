output "arn" {
  description = "ARN of the Lambda function."
  value       = module.lambda.arn
}

output "function_name" {
  description = "Name of the Lambda function."
  value       = module.lambda.function_name
}

output "qualified_arn" {
  description = "Qualified ARN of the Lambda function."
  value       = module.lambda.qualified_arn
}

output "role_arn" {
  description = "ARN of the Lambda execution role."
  value       = module.lambda.role_arn
}

output "role_name" {
  description = "Name of the Lambda execution role."
  value       = module.lambda.role_name
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for Lambda environment and secret encryption."
  value       = module.lambda.kms_key_arn
}

output "url" {
  description = "Function URL when create_url is true."
  value       = module.lambda.url
}

output "secret_arn" {
  description = "ARN of the generated secret when create_secret is true."
  value       = module.lambda.secret_arn
}

output "secret_name" {
  description = "Name of the generated secret when create_secret is true."
  value       = module.lambda.secret_name
}

output "edge_replication_policy_arn" {
  description = "ARN of the Lambda@Edge replication IAM policy."
  value       = aws_iam_policy.edge_replication.arn
}
