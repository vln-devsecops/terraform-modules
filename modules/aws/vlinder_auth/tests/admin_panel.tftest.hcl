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

  # The auth API's IAM policy interpolates the CMK ARN and the
  # session-signing-key secret's ARN; without plan-time defaults those
  # expressions (and the jsonencoded policy that embeds them) stay unknown
  # and the assertions below can't evaluate. Same reasoning as
  # lambdas.tftest.hcl's aws_kms_key mock.
  mock_resource "aws_kms_key" {
    defaults = {
      id  = "00000000-0000-0000-0000-000000000000"
      arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      id  = "auth-session-signing-key-placeholder"
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:auth-session-signing-key-placeholder"
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

mock_provider "random" {
  mock_resource "random_string" {
    defaults = {
      result = "abc12345"
    }
  }
}

variables {
  app_name               = "myapp"
  deployment_environment = "prod"
  route53_zone_id        = "Z1234567890"
  acm_certificate_arn    = "arn:aws:acm:us-east-1:123456789012:certificate/example"
}

run "auth_site_is_served_from_a_dedicated_cloudfront_distribution" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_distribution.auth_site.aliases) > 0
    error_message = "The auth site CloudFront distribution should have at least one alias."
  }

  assert {
    condition     = contains(tolist(aws_cloudfront_distribution.auth_site.aliases), "auth.devsecops.vlinder.ca")
    error_message = "The auth site distribution alias should be auth.<zone> using the default domain_prefix."
  }

  assert {
    condition     = startswith(aws_s3_bucket.auth_site.bucket, "myapp-prod-auth-site-")
    error_message = "The auth site S3 bucket should be named <app_name>-<environment>-auth-site-<random suffix>."
  }
}

run "admin_panel_is_at_the_admin_path_not_a_separate_subdomain" {
  command = plan

  assert {
    condition = alltrue([
      for rule in aws_cloudfront_distribution.auth_site.ordered_cache_behavior :
      rule.path_pattern != "*.devsecops.vlinder.ca*"
    ])
    error_message = "Admin panel must NOT be served from a separate subdomain -- it is a path (/admin) on the auth site distribution."
  }

  assert {
    condition = anytrue([
      for rule in aws_cloudfront_distribution.auth_site.ordered_cache_behavior :
      rule.path_pattern == "/api/v1/*"
    ])
    error_message = "Admin API should be accessible at /api/v1/* on the auth site distribution when create_admin_panel is true."
  }
}

run "admin_api_behavior_is_omitted_when_admin_panel_is_disabled" {
  command = plan

  variables {
    create_admin_panel = false
  }

  assert {
    condition = !anytrue([
      for rule in aws_cloudfront_distribution.auth_site.ordered_cache_behavior :
      rule.path_pattern == "/api/v1/*"
    ])
    error_message = "The /api/v1/* CloudFront behavior should not be present when create_admin_panel is false."
  }
}

run "auth_site_is_always_provisioned_regardless_of_admin_panel_flag" {
  command = plan

  variables {
    create_admin_panel = false
  }

  assert {
    condition     = length(aws_cloudfront_distribution.auth_site.aliases) > 0
    error_message = "The auth site CloudFront distribution should exist even when create_admin_panel is false."
  }

  assert {
    condition     = length(aws_s3_bucket.auth_site.bucket) > 0
    error_message = "The auth site S3 bucket should exist even when create_admin_panel is false."
  }
}

run "custom_domain_prefix_controls_auth_site_hostname" {
  command = plan

  variables {
    domain_prefix = "login"
  }

  assert {
    condition     = contains(tolist(aws_cloudfront_distribution.auth_site.aliases), "login.devsecops.vlinder.ca")
    error_message = "Custom domain_prefix should determine the auth site CloudFront alias."
  }
}

run "idp_proxy_behavior_is_retired" {
  command = plan

  # The vendor-neutral migration removed the direct-to-Cognito proxy: the SPA
  # speaks only /api/v1/auth now, so no /api/v1/idp* behavior should remain.
  assert {
    condition = alltrue([
      for rule in aws_cloudfront_distribution.auth_site.ordered_cache_behavior :
      !startswith(rule.path_pattern, "/api/v1/idp")
    ])
    error_message = "The /api/v1/idp* CloudFront behavior (retired Cognito IDP proxy) should no longer exist."
  }

  assert {
    condition = alltrue([
      for o in aws_cloudfront_distribution.auth_site.origin : o.origin_id != "CognitoIdp"
    ])
    error_message = "The Cognito-IDP custom origin should be removed with the proxy."
  }
}

run "auth_api_behavior_is_present_when_admin_panel_enabled" {
  command = plan

  assert {
    condition = anytrue([
      for rule in aws_cloudfront_distribution.auth_site.ordered_cache_behavior :
      rule.path_pattern == "/api/v1/auth*"
    ])
    error_message = "The /api/v1/auth* CloudFront behavior (vendor-neutral auth API) should be present."
  }

  # Ordering is load-bearing: /api/v1/auth* must be evaluated before /api/v1/*,
  # or auth requests fall through to the admin API.
  assert {
    condition = (
      [for i, rule in aws_cloudfront_distribution.auth_site.ordered_cache_behavior : i if rule.path_pattern == "/api/v1/auth*"][0]
      <
      [for i, rule in aws_cloudfront_distribution.auth_site.ordered_cache_behavior : i if rule.path_pattern == "/api/v1/*"][0]
    )
    error_message = "The /api/v1/auth* behavior must be ordered before /api/v1/*."
  }

  assert {
    condition     = length(aws_lambda_function.auth_api) == 1
    error_message = "The auth API Lambda should be provisioned when create_admin_panel is true."
  }

  assert {
    condition     = one(aws_lambda_function.auth_api[*].handler) == "auth-api/handler.handler"
    error_message = "The auth API Lambda should use the auth-api/handler.handler entry point."
  }
}

run "session_signing_key_is_provisioned_via_secrets_manager_not_a_terraform_generated_value" {
  command = plan

  assert {
    condition     = length(aws_secretsmanager_secret.auth_session_signing_key) == 1
    error_message = "The session-signing-key secret should be provisioned when create_admin_panel is true."
  }

  assert {
    condition     = one(aws_secretsmanager_secret.auth_session_signing_key[*].kms_key_id) == aws_kms_key.this.id
    error_message = "The session-signing-key secret should be encrypted with the module's own CMK."
  }

  assert {
    condition     = length(time_rotating.auth_session_signing_key) == 1 && one(time_rotating.auth_session_signing_key[*].rotation_days) == 30
    error_message = "The session-signing-key secret should rotate on a fixed 30-day cadence."
  }

  assert {
    condition     = one(aws_lambda_function.auth_api[*].environment[0].variables["SESSION_SIGNING_KEY_SECRET_ID"]) == one(aws_secretsmanager_secret.auth_session_signing_key[*].arn)
    error_message = "The auth API Lambda should receive the secret's ARN, not a plaintext signing key, via SESSION_SIGNING_KEY_SECRET_ID."
  }

  assert {
    condition     = !contains(keys(one(aws_lambda_function.auth_api[*].environment[0].variables)), "SESSION_SIGNING_KEY")
    error_message = "The auth API Lambda must not receive a plaintext SESSION_SIGNING_KEY env var."
  }

  assert {
    condition = anytrue([
      for stmt in jsondecode(one(aws_iam_policy.auth_api[*].policy)).Statement :
      contains(stmt.Action, "secretsmanager:GetSecretValue") &&
      contains(stmt.Resource, one(aws_secretsmanager_secret.auth_session_signing_key[*].arn))
    ])
    error_message = "The auth API Lambda's role should be able to read the session-signing-key secret, scoped to that secret's ARN."
  }

  assert {
    condition = anytrue([
      for stmt in jsondecode(one(aws_iam_policy.auth_api[*].policy)).Statement :
      contains(stmt.Action, "kms:Decrypt") && contains(stmt.Resource, aws_kms_key.this.arn)
    ])
    error_message = "The auth API Lambda's role should be able to decrypt with the module's CMK (needed for both its own env vars and the session-signing-key secret)."
  }
}

run "session_signing_key_secret_is_omitted_when_admin_panel_disabled" {
  command = plan

  variables {
    create_admin_panel = false
  }

  assert {
    condition     = length(aws_secretsmanager_secret.auth_session_signing_key) == 0
    error_message = "The session-signing-key secret should not be provisioned when create_admin_panel is false."
  }

  assert {
    condition     = length(time_rotating.auth_session_signing_key) == 0
    error_message = "The session-signing-key rotation timer should not be provisioned when create_admin_panel is false."
  }
}

run "auth_api_behavior_is_omitted_when_admin_panel_disabled" {
  command = plan

  variables {
    create_admin_panel = false
  }

  assert {
    condition = !anytrue([
      for rule in aws_cloudfront_distribution.auth_site.ordered_cache_behavior :
      rule.path_pattern == "/api/v1/auth*"
    ])
    error_message = "The /api/v1/auth* behavior should not be present when create_admin_panel is false."
  }
}
