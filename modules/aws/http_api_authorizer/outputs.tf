output "authorizer_uri" {
  description = "Lambda invoke ARN -- wire this into http_api's lambda_authorizer.authorizer_uri."
  value       = aws_lambda_function.this.invoke_arn
}

output "authorizer_function_name" {
  description = "Lambda function name -- wire this into http_api's lambda_authorizer.authorizer_function_name."
  value       = aws_lambda_function.this.function_name
}

output "jwt_forward_claims" {
  description = "The claim names configured to forward, for callers' own contract tests to assert against (e.g. that the exact claims a downstream Lambda reads are the ones actually forwarded)."
  value       = var.require_jwt ? var.jwt_forward_claims : null
}

output "origin_verify_secret" {
  description = "The generated shared secret. Wire this into your CDN's origin config as a custom request header named X-Origin-Verify (e.g. CloudFront's origin custom_header) -- the authorizer checks that exact header name, it is not caller-configurable."
  value       = random_password.origin_verify_secret.result
  sensitive   = true
}
