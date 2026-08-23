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

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
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

run "defaults_match_doxchange_derived_contract" {
  command = plan

  assert {
    condition     = aws_cognito_user_pool.this.name == "myapp-prod-user-pool"
    error_message = "User pool naming changed unexpectedly."
  }

  assert {
    condition = (
      one(aws_cognito_user_pool.this.password_policy).minimum_length == 8 &&
      one(aws_cognito_user_pool.this.password_policy).require_lowercase &&
      one(aws_cognito_user_pool.this.password_policy).require_uppercase &&
      one(aws_cognito_user_pool.this.password_policy).require_numbers &&
      one(aws_cognito_user_pool.this.password_policy).require_symbols &&
      one(aws_cognito_user_pool.this.password_policy).temporary_password_validity_days == 7
    )
    error_message = "Password policy defaults changed unexpectedly."
  }

  assert {
    condition     = aws_cognito_user_pool.this.mfa_configuration == "OFF"
    error_message = "MFA should default to OFF."
  }

  assert {
    condition     = one(aws_cognito_user_pool.this.user_pool_add_ons).advanced_security_mode == "OFF"
    error_message = "advanced_security_mode should default to OFF (AUDIT/ENFORCED require a paid Cognito feature plan -- see doc/auth-api-rate-limiting.md)."
  }

  assert {
    condition     = one(aws_cognito_user_pool.this.admin_create_user_config).allow_admin_create_user_only == false
    error_message = "allow_self_signup defaulting to true should permit public signup."
  }

  assert {
    condition     = aws_cognito_user_pool.this.auto_verified_attributes == toset(["email"])
    error_message = "Email should be auto-verified by default."
  }

  assert {
    condition     = contains(tolist(one(aws_cloudfront_distribution.auth_site[*].aliases)), "auth.devsecops.vlinder.ca")
    error_message = "Auth site CloudFront distribution alias should default to auth.<zone>."
  }

  assert {
    condition     = length(aws_cognito_identity_pool.this) == 0
    error_message = "Identity pool should be omitted by default."
  }
}

run "custom_domain_prefix_and_self_signup_disabled" {
  command = plan

  variables {
    domain_prefix     = "login"
    allow_self_signup = false
  }

  assert {
    condition     = contains(tolist(one(aws_cloudfront_distribution.auth_site[*].aliases)), "login.devsecops.vlinder.ca")
    error_message = "Custom domain_prefix should control the auth site CloudFront alias."
  }

  assert {
    condition     = one(aws_cognito_user_pool.this.admin_create_user_config).allow_admin_create_user_only == true
    error_message = "allow_self_signup = false should disable public signup pool-wide."
  }
}

run "consumer_clients_map_produces_matching_clients_plus_the_auth_site_client" {
  command = plan

  variables {
    clients = {
      webapp = {
        callback_urls = ["https://app.example.com/callback"]
        logout_urls   = ["https://app.example.com/logout"]
      }
    }
  }

  assert {
    condition     = length(aws_cognito_user_pool_client.consumer) == 1
    error_message = "One consumer client should be created per clients map entry."
  }

  assert {
    condition     = aws_cognito_user_pool_client.consumer["webapp"].callback_urls == toset(["https://app.example.com/callback"])
    error_message = "Consumer client callback_urls should be passed through."
  }

  assert {
    condition     = length(aws_cognito_user_pool_client.auth_site) == 1
    error_message = "The auth site client should be created whenever the auth site exists (auth_profile \"full\", the default)."
  }
}

run "auth_site_client_uses_server_side_admin_auth_flow" {
  command = plan

  assert {
    condition     = contains(one(aws_cognito_user_pool_client.auth_site[*].explicit_auth_flows), "ALLOW_ADMIN_USER_PASSWORD_AUTH")
    error_message = "The auth site client must enable ALLOW_ADMIN_USER_PASSWORD_AUTH for the auth Lambda's server-side sign-in."
  }

  assert {
    condition     = !contains(one(aws_cognito_user_pool_client.auth_site[*].explicit_auth_flows), "ALLOW_USER_PASSWORD_AUTH")
    error_message = "The retired direct-IDP browser flow (ALLOW_USER_PASSWORD_AUTH) should no longer be enabled."
  }

  assert {
    condition     = one(aws_cognito_user_pool_client.auth_site[*].allowed_oauth_flows_user_pool_client) == false
    error_message = "The auth site client must not use OAuth/hosted-UI redirect flows."
  }
}

run "auth_site_client_is_present_for_the_auth_api_profile" {
  command = plan

  variables {
    auth_profile = "auth_api"
  }

  assert {
    condition     = length(aws_cognito_user_pool_client.auth_site) == 1
    error_message = "The auth site client is shared by the login and admin SPAs -- it should still be created in the auth_api profile (admin panel off, login on)."
  }
}

run "auth_site_client_is_omitted_for_the_identity_only_profile" {
  command = plan

  variables {
    auth_profile = "identity_only"
  }

  assert {
    condition     = length(aws_cognito_user_pool_client.auth_site) == 0
    error_message = "The auth site client should not be created in the identity_only profile -- there is no site to log into."
  }
}

run "core_identity_endpoint_still_works_for_the_identity_only_profile" {
  command = plan

  # The identity_only profile is meant for adopters bringing their own
  # frontend, integrating directly against Cognito -- so the core identity
  # outputs must remain fully populated even though every optional layer
  # (auth API, admin API, auth site) is stripped.
  variables {
    auth_profile = "identity_only"
  }

  assert {
    condition     = length(aws_cognito_user_pool.this.id) > 0
    error_message = "The Cognito user pool must still be created in the identity_only profile."
  }

  assert {
    condition     = output.user_pool_id != null && output.user_pool_id != ""
    error_message = "user_pool_id output must be populated in the identity_only profile."
  }

  assert {
    condition     = output.user_pool_arn != null && output.user_pool_arn != ""
    error_message = "user_pool_arn output must be populated in the identity_only profile."
  }

  assert {
    condition     = output.issuer_url != null && strcontains(output.issuer_url, aws_cognito_user_pool.this.id)
    error_message = "issuer_url output must be populated and derived from this module's user pool in the identity_only profile -- adopters integrate directly against it."
  }

  assert {
    condition     = output.role_assignments_table_name != null && output.role_assignments_table_name != ""
    error_message = "role_assignments_table_name output must be populated in the identity_only profile -- RBAC is unconditional."
  }

  assert {
    condition     = output.auth_domain == null
    error_message = "auth_domain should be null in the identity_only profile -- no site is provisioned."
  }

  assert {
    condition     = output.auth_url == null
    error_message = "auth_url should be null in the identity_only profile."
  }

  assert {
    condition     = output.auth_site_bucket_name == null
    error_message = "auth_site_bucket_name should be null in the identity_only profile."
  }

  assert {
    condition     = output.admin_panel_url == null
    error_message = "admin_panel_url should be null in the identity_only profile."
  }

  assert {
    condition     = output.admin_api_invoke_url == null
    error_message = "admin_api_invoke_url should be null in the identity_only profile."
  }

  assert {
    condition     = output.auth_site_client_id == null
    error_message = "auth_site_client_id should be null in the identity_only profile."
  }
}

run "groups_are_created_from_the_groups_map" {
  command = plan

  variables {
    groups = {
      staff = {
        description = "Internal staff"
        precedence  = 5
      }
    }
  }

  assert {
    condition     = length(aws_cognito_user_group.this) == 1
    error_message = "One group should be created per groups map entry."
  }

  assert {
    condition     = aws_cognito_user_group.this["staff"].precedence == 5
    error_message = "Group precedence should be passed through."
  }
}

run "advanced_security_mode_override_is_plumbed_through" {
  command = plan

  variables {
    advanced_security_mode = "AUDIT"
  }

  assert {
    condition     = one(aws_cognito_user_pool.this.user_pool_add_ons).advanced_security_mode == "AUDIT"
    error_message = "advanced_security_mode override should be passed through to user_pool_add_ons."
  }
}

run "identity_pool_is_created_when_requested" {
  command = plan

  variables {
    create_identity_pool = true
  }

  assert {
    condition     = length(aws_cognito_identity_pool.this) == 1
    error_message = "Identity pool should be created when create_identity_pool is true."
  }
}
