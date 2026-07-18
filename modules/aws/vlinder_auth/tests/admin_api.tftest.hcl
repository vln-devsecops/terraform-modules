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

run "admin_api_is_provisioned_via_the_shared_http_api_module_with_a_jwt_authorizer_on_this_pool" {
  command = plan

  assert {
    condition     = length(module.admin_api) == 1
    error_message = "The admin API should be provisioned via the shared http_api module when create_admin_panel is true (the default)."
  }

  # http_api is a separate module with its own test suite that verifies
  # jwt_authorizers.issuer_url actually lands in the authorizer resource;
  # module encapsulation means only outputs are visible from here, so this
  # checks the value vlinder_auth itself computes and hands across that
  # boundary, not http_api's internals.
  assert {
    condition     = strcontains(local.admin_api_issuer_url, "us-east-1_exampleId")
    error_message = "The admin API's JWT authorizer issuer should be derived from this module's own user pool."
  }
}

run "admin_api_is_omitted_when_admin_panel_is_disabled" {
  command = plan

  variables {
    create_admin_panel = false
  }

  assert {
    condition     = length(module.admin_api) == 0
    error_message = "The admin API should not be provisioned when create_admin_panel is false."
  }

  assert {
    condition     = length(aws_lambda_function.admin_api) == 0
    error_message = "The admin-api Lambda itself should not be provisioned when create_admin_panel is false."
  }
}

run "admin_api_routes_cover_the_full_users_and_roles_surface" {
  command = plan

  assert {
    condition = alltrue([
      for route_key in [
        "GET /users", "GET /users/{userId}", "PATCH /users/{userId}/enabled",
        "GET /roles", "PUT /users/{userId}/roles/{roleId}", "DELETE /users/{userId}/roles/{roleId}",
      ] :
      contains([for route in local.admin_api_routes : route.route_key], route_key)
    ])
    error_message = "The admin API should expose a route for every admin-api handler entrypoint (matches lambda-src's own routeKey switch)."
  }
}
