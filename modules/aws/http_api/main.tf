locals {
  # Effective authorization type per route: explicit when set, otherwise derived
  # from whether the route references a JWT authorizer.
  route_authorization_types = {
    for route_key, route in var.routes :
    route_key => coalesce(route.authorization_type, route.authorizer_key != null ? "JWT" : "NONE")
  }

  # Build a flat map of route_key → authorizer_id for routes that reference an authorizer
  route_authorizer_ids = {
    for route_key, route in var.routes :
    route_key => aws_apigatewayv2_authorizer.jwt[route.authorizer_key].id
    if route.authorizer_key != null
  }

  # CloudWatch log group names allow alphanumeric, underscore, hyphen, slash, hash, and dot.
  sanitized_stage_name = replace(var.stage_name, "/[^0-9A-Za-z_/#.-]/", "-")
}

resource "aws_apigatewayv2_api" "this" {
  name          = var.name
  protocol_type = "HTTP"
  description   = var.description

  dynamic "cors_configuration" {
    for_each = var.cors_configuration != null ? [var.cors_configuration] : []
    content {
      allow_origins     = cors_configuration.value.allow_origins
      allow_methods     = cors_configuration.value.allow_methods
      allow_headers     = cors_configuration.value.allow_headers
      expose_headers    = cors_configuration.value.expose_headers
      max_age           = cors_configuration.value.max_age
      allow_credentials = cors_configuration.value.allow_credentials
    }
  }

  tags = var.tags
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  for_each = var.jwt_authorizers

  api_id           = aws_apigatewayv2_api.this.id
  authorizer_type  = "JWT"
  name             = each.key
  identity_sources = each.value.identity_sources

  jwt_configuration {
    issuer   = each.value.issuer_url
    audience = each.value.audience
  }
}

resource "aws_apigatewayv2_authorizer" "lambda" {
  count = var.lambda_authorizer != null ? 1 : 0

  api_id                            = aws_apigatewayv2_api.this.id
  authorizer_type                   = "REQUEST"
  name                              = "${var.name}-lambda-authorizer"
  authorizer_uri                    = var.lambda_authorizer.authorizer_uri
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  identity_sources                  = var.lambda_authorizer.identity_sources
  authorizer_result_ttl_in_seconds  = var.lambda_authorizer.result_ttl_in_seconds
}

resource "aws_lambda_permission" "authorizer_invoke" {
  count = var.lambda_authorizer != null ? 1 : 0

  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_authorizer.authorizer_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/authorizers/${aws_apigatewayv2_authorizer.lambda[0].id}"
}

resource "aws_cloudwatch_log_group" "access_logs" {
  count = var.create_access_log_group ? 1 : 0

  name              = "/aws/apigateway/${var.name}/${local.sanitized_stage_name}"
  retention_in_days = var.access_log_retention_days
  tags              = var.tags
}

resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = var.stage_name
  auto_deploy = var.auto_deploy

  dynamic "access_log_settings" {
    for_each = var.create_access_log_group ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.access_logs[0].arn
      format          = var.access_log_format
    }
  }

  dynamic "route_settings" {
    for_each = { for k, v in var.routes : k => v if v.throttling_burst_limit != null || v.throttling_rate_limit != null }
    content {
      route_key              = route_settings.value.route_key
      throttling_burst_limit = route_settings.value.throttling_burst_limit
      throttling_rate_limit  = route_settings.value.throttling_rate_limit
    }
  }

  tags = var.tags
}

resource "aws_apigatewayv2_integration" "this" {
  for_each = var.routes

  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = each.value.lambda_function_arn
  payload_format_version = each.value.payload_format_version
  timeout_milliseconds   = each.value.timeout_milliseconds
}

resource "aws_apigatewayv2_route" "this" {
  for_each = var.routes

  api_id    = aws_apigatewayv2_api.this.id
  route_key = each.value.route_key
  target    = "integrations/${aws_apigatewayv2_integration.this[each.key].id}"

  authorization_type = local.route_authorization_types[each.key]
  authorizer_id = (
    local.route_authorization_types[each.key] == "CUSTOM"
    ? try(aws_apigatewayv2_authorizer.lambda[0].id, null)
    : try(local.route_authorizer_ids[each.key], null)
  )
}

resource "aws_lambda_permission" "this" {
  for_each = var.routes

  statement_id  = "AllowAPIGateway-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

resource "aws_apigatewayv2_domain_name" "this" {
  count = var.custom_domain_name != null ? 1 : 0

  domain_name = var.custom_domain_name

  domain_name_configuration {
    certificate_arn = var.custom_domain_certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = var.tags
}

resource "aws_apigatewayv2_api_mapping" "this" {
  count = var.custom_domain_name != null ? 1 : 0

  api_id          = aws_apigatewayv2_api.this.id
  domain_name     = aws_apigatewayv2_domain_name.this[0].id
  stage           = aws_apigatewayv2_stage.this.id
  api_mapping_key = var.api_mapping_key
}

resource "aws_route53_record" "custom_domain" {
  count = var.custom_domain_name != null ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.custom_domain_name
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}
