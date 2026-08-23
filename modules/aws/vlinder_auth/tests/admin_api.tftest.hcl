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

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
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

run "admin_api_is_provisioned_via_the_shared_http_api_module_with_a_lambda_authorizer_that_also_verifies_jwts" {
  command = plan

  assert {
    condition     = length(module.admin_api) == 1
    error_message = "The admin API should be provisioned via the shared http_api module when auth_profile is \"full\" (the default)."
  }

  assert {
    condition     = length(module.admin_api_authorizer) == 1
    error_message = "The admin API should get its own http_api_authorizer instance, require_jwt = true, when auth_profile is \"full\"."
  }

  # http_api and http_api_authorizer are separate modules with their own test
  # suites verifying jwt_issuer_url actually lands in the authorizer Lambda's
  # env vars; module encapsulation means only outputs are visible from here,
  # so this checks the value vlinder_auth itself computes and hands across
  # that boundary, not either module's internals.
  assert {
    condition     = strcontains(local.admin_api_issuer_url, "us-east-1_exampleId")
    error_message = "The admin API authorizer's JWT issuer should be derived from this module's own user pool."
  }

  # Every admin route must go through the Lambda authorizer (origin-verify +
  # JWT), not the old per-route JWT authorizer_key mechanism -- see
  # doc/../http_api's CUSTOM authorization_type.
  assert {
    condition = alltrue([
      for route in local.admin_api_routes : route.authorization_type == "CUSTOM"
    ])
    error_message = "Every admin API route must have authorization_type CUSTOM, wired to the shared Lambda authorizer."
  }
}

run "admin_api_is_omitted_for_the_auth_api_profile" {
  command = plan

  variables {
    auth_profile = "auth_api"
  }

  assert {
    condition     = length(module.admin_api) == 0
    error_message = "The admin API should not be provisioned in the auth_api profile."
  }

  assert {
    condition     = length(aws_lambda_function.admin_api) == 0
    error_message = "The admin-api Lambda itself should not be provisioned in the auth_api profile."
  }
}

run "admin_api_is_omitted_for_the_identity_only_profile" {
  command = plan

  variables {
    auth_profile = "identity_only"
  }

  assert {
    condition     = length(module.admin_api) == 0
    error_message = "The admin API should not be provisioned in the identity_only profile."
  }

  assert {
    condition     = length(aws_lambda_function.admin_api) == 0
    error_message = "The admin-api Lambda itself should not be provisioned in the identity_only profile."
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

run "admin_api_never_exposes_a_post_route" {
  command = plan

  # admin_api_rewrite.js (the CloudFront viewer-request function on /api/v1/*)
  # lifts the vln_auth_session cookie into the Authorization header, which
  # turns the admin API from bearer-token semantics (CSRF-immune) into cookie
  # semantics (CSRF-relevant) for anything a browser can be tricked into
  # submitting. Today that's contained only because every admin route is
  # PATCH/PUT/DELETE -- none of which a plain HTML form can send, so there's
  # no cross-site request a victim's browser could issue that would carry the
  # cookie. A POST route would be form-submittable and reopen that gap, so
  # this must never silently regain one. See doc/admin-api-csrf.md for the
  # full posture and what to build (double-submit token) if this ever needs
  # to change.
  assert {
    condition = alltrue([
      for route in local.admin_api_routes : !startswith(route.route_key, "POST ")
    ])
    error_message = "The admin API must not expose a POST route: the CloudFront cookie-to-Authorization-header lift makes state-changing routes CSRF-relevant, and only non-form-submittable methods (PATCH/PUT/DELETE) keep that safe."
  }
}
