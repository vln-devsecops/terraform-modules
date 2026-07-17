output "table_name" {
  description = "DynamoDB table name backing contact form submissions."
  value       = module.table.table_name
}

output "table_arn" {
  description = "DynamoDB table ARN backing contact form submissions."
  value       = module.table.table_arn
}

output "submit_function_name" {
  description = "Name of the public submit Lambda function."
  value       = aws_lambda_function.submit.function_name
}

output "submit_function_url" {
  description = "Public HTTPS endpoint for form submissions (Function URL, no auth). Wire this into the consuming site's contact form as its POST target."
  value       = aws_lambda_function_url.submit.function_url
}

output "admin_function_name" {
  description = "Name of the AWS_IAM-authorized admin Lambda function."
  value       = aws_lambda_function.admin.function_name
}

output "admin_function_url" {
  description = "AWS_IAM-authorized HTTPS endpoint for listing/reading/deleting submissions. Callers must SigV4-sign requests and be listed in admin_allowed_principal_arns."
  value       = aws_lambda_function_url.admin.function_url
}

output "recaptcha_secret_arn" {
  description = "Secrets Manager ARN for the reCAPTCHA v3 secret key. Terraform only creates a placeholder value -- populate the real secret out of band (e.g. aws secretsmanager put-secret-value) before the submit Lambda can verify submissions."
  value       = aws_secretsmanager_secret.recaptcha.arn
}
