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

output "auth_domain" {
  description = "Auth site domain (CloudFront alias for the login and admin SPA)."
  value       = local.auth_site_domain
}

output "auth_url" {
  description = "Base HTTPS URL for the auth site (login SPA)."
  value       = "https://${local.auth_site_domain}"
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
  description = "URL for the admin panel within the auth site, when create_admin_panel is true; null otherwise."
  value       = var.create_admin_panel ? "https://${local.auth_site_domain}/admin" : null
}

output "admin_api_invoke_url" {
  description = "Invoke URL for the bundled admin API, when create_admin_panel is true; null otherwise. A deploy pipeline injects this into the auth site's runtime config."
  value       = one(module.admin_api[*].invoke_url)
}

output "auth_site_client_id" {
  description = "Cognito app client ID for the bundled auth site, when create_admin_panel is true; null otherwise. The module writes this into the SPA's runtime config.json itself; exposed for test/ops tooling."
  value       = one(aws_cognito_user_pool_client.auth_site[*].id)
}

output "auth_site_bucket_name" {
  description = "S3 bucket name for the auth site SPA static assets. The module deploys the SPA here itself; exposed for test/ops tooling that needs to inspect the bucket."
  value       = aws_s3_bucket.auth_site.id
}

output "role_assignments_table_name" {
  description = "DynamoDB table name backing user role assignments. Exposed for test/ops tooling that needs to seed or inspect role assignments directly (e.g. bootstrapping the first admin) -- normal app code should go through the admin API, not this table, wherever possible."
  value       = module.user_role_assignments.table_name
}
