output "api_id" {
  description = "API Gateway HTTP API ID."
  value       = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "Default API endpoint (invoke URL without stage)."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "execution_arn" {
  description = "Execution ARN for use in Lambda permissions."
  value       = aws_apigatewayv2_api.this.execution_arn
}

output "stage_name" {
  description = "Deployed stage name."
  value       = aws_apigatewayv2_stage.this.name
}

output "invoke_url" {
  description = "Full invocation URL including stage."
  value       = var.stage_name == "$default" ? aws_apigatewayv2_api.this.api_endpoint : "${aws_apigatewayv2_api.this.api_endpoint}/${var.stage_name}"
}

output "custom_domain_name" {
  description = "Custom domain name, if configured."
  value       = var.custom_domain_name != null ? aws_apigatewayv2_domain_name.this[0].domain_name : null
}

output "domain_name_target" {
  description = "Target domain name of the custom domain's API Gateway endpoint (for Route 53 alias)."
  value       = var.custom_domain_name != null ? aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].target_domain_name : null
}

output "domain_name_hosted_zone_id" {
  description = "Hosted zone ID of the custom domain's API Gateway endpoint (for Route 53 alias)."
  value       = var.custom_domain_name != null ? aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].hosted_zone_id : null
}
