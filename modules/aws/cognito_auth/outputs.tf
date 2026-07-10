output "user_pool_id" {
  description = "Cognito user pool ID."
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "Cognito user pool ARN."
  value       = aws_cognito_user_pool.this.arn
}

output "issuer_url" {
  description = "OIDC issuer URL for this user pool. Wire this into your own app's http_api jwt_authorizers to authorize against tokens this module issues."
  value       = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
}

output "hosted_ui_domain" {
  description = "Cognito hosted-UI custom domain."
  value       = aws_cognito_user_pool_domain.this.domain
}

output "hosted_ui_url" {
  description = "Base HTTPS URL for the Cognito hosted UI."
  value       = "https://${aws_cognito_user_pool_domain.this.domain}"
}

output "client_ids" {
  description = "Map of consumer app client IDs, keyed the same as var.clients."
  value       = { for key, client in aws_cognito_user_pool_client.consumer : key => client.id }
}

output "identity_pool_id" {
  description = "Cognito identity pool ID, when create_identity_pool is true; null otherwise."
  value       = one(aws_cognito_identity_pool.this[*].id)
}

output "admin_panel_url" {
  description = "Base HTTPS URL for the bundled admin panel, when create_admin_panel is true; null otherwise."
  value       = one(module.admin_panel_site[*].site_url)
}

output "admin_api_invoke_url" {
  description = "Invoke URL for the bundled admin API, when create_admin_panel is true; null otherwise. A deploy pipeline injects this into the admin panel's runtime config."
  value       = one(module.admin_api[*].invoke_url)
}

output "admin_panel_client_id" {
  description = "Cognito app client ID for the bundled admin panel, when create_admin_panel is true; null otherwise."
  value       = one(aws_cognito_user_pool_client.admin_panel[*].id)
}
