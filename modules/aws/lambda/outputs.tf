output "arn" {
  description = "ARN of the Lambda function."
  value       = aws_lambda_function.this.arn
}

output "function_name" {
  description = "Name of the Lambda function."
  value       = aws_lambda_function.this.function_name
}

output "qualified_arn" {
  description = "Qualified ARN of the Lambda function."
  value       = aws_lambda_function.this.qualified_arn
}

output "role_arn" {
  description = "ARN of the Lambda execution role."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the Lambda execution role."
  value       = aws_iam_role.this.name
}

output "url" {
  description = "Function URL when create_url is true."
  value       = try(aws_lambda_function_url.this[0].function_url, null)
}

output "secret_arn" {
  description = "ARN of the generated secret when create_secret is true."
  value       = try(aws_secretsmanager_secret.this[0].arn, null)
}

output "secret_name" {
  description = "Name of the generated secret when create_secret is true."
  value       = try(aws_secretsmanager_secret.this[0].name, null)
}
