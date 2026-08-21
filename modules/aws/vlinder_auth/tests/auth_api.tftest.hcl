mock_provider "aws" {
  override_during = plan

  mock_data "aws_route53_zone" {
    defaults = {
      name = "devsecops.vlinder.ca."
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_cognito_user_pool" {
    defaults = {
      id  = "us-east-1_exampleId"
      arn = "arn:aws:cognito-idp:us-east-1:123456789012:userpool/us-east-1_exampleId"
    }
  }

  mock_resource "aws_cognito_user_pool_client" {
    defaults = {
      id = "clientidplaceholder"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      arn = "arn:aws:lambda:us-east-1:123456789012:function:placeholder"
    }
  }

  mock_resource "aws_dynamodb_table" {
    defaults = {
      arn = "arn:aws:dynamodb:us-east-1:123456789012:table/placeholder"
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      id                             = "EDFDVBD632BHDS5"
      arn                            = "arn:aws:cloudfront::123456789012:distribution/EDFDVBD632BHDS5"
      domain_name                    = "d111111abcdef8.cloudfront.net"
      hosted_zone_id                 = "Z2FDTNDATAQYW2"
      status                         = "Deployed"
      etag                           = "test"
      in_progress_validation_batches = 0
      web_acl_id                     = null
    }
  }

  mock_resource "aws_cloudfront_function" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:function/test"
    }
  }

  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      id            = "apiplaceholder"
      api_endpoint  = "https://apiplaceholder.execute-api.us-east-1.amazonaws.com"
      execution_arn = "arn:aws:execute-api:us-east-1:123456789012:apiplaceholder"
    }
  }
}

mock_provider "archive" {
  override_during = plan

  mock_data "archive_file" {
    defaults = {
      output_path         = "/tmp/placeholder.zip"
      output_base64sha256 = "YWJjZGVm"
      output_size         = 128
    }
  }
}

variables {
  app_name               = "myapp"
  deployment_environment = "prod"
  route53_zone_id        = "Z1234567890"
  acm_certificate_arn    = "arn:aws:acm:us-east-1:123456789012:certificate/example"
}

run "auth_api_routes_are_throttled_with_the_default_limits" {
  command = plan

  # auth_api_rewrite.js and the /api/v1/auth* CloudFront behavior make these
  # 7 routes unauthenticated by design -- see doc/auth-api-rate-limiting.md
  # for why they're throttled (aggregate, not per-IP) and default to a
  # no-extra-cost burst/rate pair.
  assert {
    condition = alltrue([
      for route in local.auth_api_routes :
      route.throttling_burst_limit == 10 && route.throttling_rate_limit == 5
    ])
    error_message = "Every public /auth/* route should carry the default auth_api_throttling limits (burst_limit=10, rate_limit=5)."
  }

  assert {
    condition = alltrue([
      for route_key in [
        "POST /auth/identify", "POST /auth/password", "POST /auth/signup",
        "POST /auth/confirm", "POST /auth/resend", "POST /auth/forgot", "POST /auth/reset",
      ] :
      contains([for route in local.auth_api_routes : route.route_key], route_key)
    ])
    error_message = "The full public auth surface should be present in local.auth_api_routes."
  }
}

run "auth_api_throttling_override_is_plumbed_through_to_every_route" {
  command = plan

  variables {
    auth_api_throttling = {
      burst_limit = 20
      rate_limit  = 10
    }
  }

  assert {
    condition = alltrue([
      for route in local.auth_api_routes :
      route.throttling_burst_limit == 20 && route.throttling_rate_limit == 10
    ])
    error_message = "auth_api_throttling overrides should apply to every public /auth/* route."
  }
}

run "auth_api_routes_are_omitted_when_admin_panel_is_disabled" {
  command = plan

  variables {
    create_admin_panel = false
  }

  assert {
    condition     = length(local.auth_api_routes) == 0
    error_message = "auth_api_routes should be empty when create_admin_panel is false."
  }

  assert {
    condition     = length(module.auth_api) == 0
    error_message = "The auth_api module should not be provisioned when create_admin_panel is false."
  }
}
