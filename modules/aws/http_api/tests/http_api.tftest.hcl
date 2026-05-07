mock_provider "aws" {
  override_during = plan

  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      id            = "abc1234567"
      api_endpoint  = "https://abc1234567.execute-api.eu-west-1.amazonaws.com"
      execution_arn = "arn:aws:execute-api:eu-west-1:123456789012:abc1234567"
    }
  }
  mock_resource "aws_apigatewayv2_stage" {
    defaults = { id = "abc1234567/$default" }
  }
  mock_resource "aws_apigatewayv2_integration" {
    defaults = { id = "mock-integration-id" }
  }
  mock_resource "aws_apigatewayv2_route" {
    defaults = {}
  }
  mock_resource "aws_lambda_permission" {
    defaults = {}
  }
  mock_resource "aws_apigatewayv2_authorizer" {
    defaults = { id = "mock-authorizer-id" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/apigateway/test" }
  }
  mock_resource "aws_apigatewayv2_domain_name" {
    defaults = {
      domain_name = "api.example.com"
      domain_name_configuration = {
        certificate_arn    = "arn:aws:acm:eu-west-1:123456789012:certificate/example"
        endpoint_type      = "REGIONAL"
        security_policy    = "TLS_1_2"
        target_domain_name = "d-example.execute-api.eu-west-1.amazonaws.com"
        hosted_zone_id     = "Z2RPCDW04V8134"
      }
    }
  }
  mock_resource "aws_apigatewayv2_api_mapping" {
    defaults = {}
  }
  mock_resource "aws_route53_record" {
    defaults = {}
  }
}

run "api_with_no_routes_creates_empty_api" {
  command = plan

  variables {
    name = "empty-api"
  }

  assert {
    condition     = aws_apigatewayv2_api.this.name == "empty-api"
    error_message = "API name was not set correctly."
  }

  assert {
    condition     = aws_apigatewayv2_api.this.protocol_type == "HTTP"
    error_message = "API protocol type must be HTTP."
  }

  assert {
    condition     = length(aws_apigatewayv2_route.this) == 0
    error_message = "No routes should be created when routes map is empty."
  }

  assert {
    condition     = length(aws_apigatewayv2_integration.this) == 0
    error_message = "No integrations should be created when routes map is empty."
  }

  assert {
    condition     = length(aws_lambda_permission.this) == 0
    error_message = "No Lambda permissions should be created when routes map is empty."
  }

  assert {
    condition     = output.api_id == "abc1234567"
    error_message = "api_id output must match the created API."
  }

  assert {
    condition     = output.stage_name == "$default"
    error_message = "stage_name output must default to $default."
  }
}

run "two_routes_create_integrations_and_lambda_permissions" {
  command = plan

  variables {
    name = "two-route-api"
    routes = {
      get_items = {
        route_key            = "GET /items"
        lambda_function_arn  = "arn:aws:lambda:eu-west-1:123456789012:function:get-items"
        lambda_function_name = "get-items"
      }
      post_items = {
        route_key            = "POST /items"
        lambda_function_arn  = "arn:aws:lambda:eu-west-1:123456789012:function:post-items"
        lambda_function_name = "post-items"
      }
    }
  }

  assert {
    condition     = length(aws_apigatewayv2_route.this) == 2
    error_message = "Expected exactly 2 routes."
  }

  assert {
    condition     = length(aws_apigatewayv2_integration.this) == 2
    error_message = "Expected exactly 2 integrations."
  }

  assert {
    condition     = length(aws_lambda_permission.this) == 2
    error_message = "Expected exactly 2 Lambda permissions."
  }

  assert {
    condition     = aws_apigatewayv2_route.this["get_items"].route_key == "GET /items"
    error_message = "get_items route key is incorrect."
  }

  assert {
    condition     = aws_apigatewayv2_route.this["post_items"].route_key == "POST /items"
    error_message = "post_items route key is incorrect."
  }

  assert {
    condition     = aws_lambda_permission.this["get_items"].function_name == "get-items"
    error_message = "get_items Lambda permission function name is incorrect."
  }

  assert {
    condition     = aws_lambda_permission.this["post_items"].function_name == "post-items"
    error_message = "post_items Lambda permission function name is incorrect."
  }
}

run "jwt_authorizer_is_wired_to_protected_route" {
  command = plan

  variables {
    name = "auth-api"
    jwt_authorizers = {
      coppice = {
        issuer_url = "https://auth.example.com"
        audience   = ["api.example.com"]
      }
    }
    routes = {
      public_route = {
        route_key            = "GET /public"
        lambda_function_arn  = "arn:aws:lambda:eu-west-1:123456789012:function:public-fn"
        lambda_function_name = "public-fn"
      }
      protected_route = {
        route_key            = "POST /protected"
        lambda_function_arn  = "arn:aws:lambda:eu-west-1:123456789012:function:protected-fn"
        lambda_function_name = "protected-fn"
        authorizer_key       = "coppice"
      }
    }
  }

  assert {
    condition     = length(aws_apigatewayv2_authorizer.jwt) == 1
    error_message = "Expected exactly one JWT authorizer."
  }

  assert {
    condition     = aws_apigatewayv2_authorizer.jwt["coppice"].authorizer_type == "JWT"
    error_message = "Authorizer type must be JWT."
  }

  assert {
    condition     = aws_apigatewayv2_route.this["protected_route"].authorization_type == "JWT"
    error_message = "Protected route must have authorization_type JWT."
  }

  assert {
    condition     = aws_apigatewayv2_route.this["public_route"].authorization_type == "NONE"
    error_message = "Public route must have authorization_type NONE."
  }
}

run "custom_domain_creates_domain_name_and_route53_record" {
  command = plan

  variables {
    name                          = "domain-api"
    custom_domain_name            = "api.example.com"
    custom_domain_certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/example"
    route53_zone_id               = "Z2RPCDW04V8134"
  }

  assert {
    condition     = length(aws_apigatewayv2_domain_name.this) == 1
    error_message = "Expected exactly one custom domain name resource."
  }

  assert {
    condition     = length(aws_route53_record.custom_domain) == 1
    error_message = "Expected exactly one Route 53 record."
  }

  assert {
    condition     = length(aws_apigatewayv2_api_mapping.this) == 1
    error_message = "Expected exactly one API mapping."
  }

  assert {
    condition     = output.custom_domain_name == "api.example.com"
    error_message = "custom_domain_name output must reflect the configured domain."
  }

  assert {
    condition     = output.domain_name_target == "d-example.execute-api.eu-west-1.amazonaws.com"
    error_message = "domain_name_target output must be populated from the domain name configuration."
  }

  assert {
    condition     = output.domain_name_hosted_zone_id == "Z2RPCDW04V8134"
    error_message = "domain_name_hosted_zone_id output must be populated from the domain name configuration."
  }
}

run "cors_configuration_is_applied_when_provided" {
  command = plan

  variables {
    name = "cors-api"
    cors_configuration = {
      allow_origins = ["https://example.com"]
      allow_methods = ["GET", "POST", "OPTIONS"]
      allow_headers = ["Content-Type", "Authorization"]
      max_age       = 600
    }
  }

  assert {
    condition     = length(aws_apigatewayv2_api.this.cors_configuration) > 0
    error_message = "CORS configuration block must be present when cors_configuration is provided."
  }

  assert {
    condition     = contains(aws_apigatewayv2_api.this.cors_configuration[0].allow_origins, "https://example.com")
    error_message = "CORS allow_origins must include the configured origin."
  }

  assert {
    condition     = aws_apigatewayv2_api.this.cors_configuration[0].max_age == 600
    error_message = "CORS max_age must be 600."
  }
}
