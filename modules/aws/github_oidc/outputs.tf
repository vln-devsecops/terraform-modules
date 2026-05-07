output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC identity provider. When create_oidc_provider is false this is derived from the current account ID rather than read from a managed resource."
  value       = local.oidc_provider_arn
}

output "role_arns" {
  description = "Map of role key (as defined in var.roles) to the ARN of the created IAM role."
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}
