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

  mock_resource "aws_cognito_user_pool_domain" {
    defaults = {
      cloudfront_distribution         = "d111111abcdef8.cloudfront.net"
      cloudfront_distribution_zone_id = "Z2FDTNDATAQYW2"
    }
  }

  mock_resource "aws_cognito_user_pool_client" {
    defaults = {
      id = "clientidplaceholder"
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
    condition     = one(aws_cognito_user_pool.this.admin_create_user_config).allow_admin_create_user_only == false
    error_message = "allow_self_signup defaulting to true should permit public signup."
  }

  assert {
    condition     = aws_cognito_user_pool.this.auto_verified_attributes == toset(["email"])
    error_message = "Email should be auto-verified by default."
  }

  assert {
    condition     = aws_cognito_user_pool_domain.this.domain == "auth.devsecops.vlinder.ca"
    error_message = "Hosted-UI domain should default to the auth prefix over the zone's base domain."
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
    condition     = aws_cognito_user_pool_domain.this.domain == "login.devsecops.vlinder.ca"
    error_message = "Custom domain_prefix should be honored."
  }

  assert {
    condition     = one(aws_cognito_user_pool.this.admin_create_user_config).allow_admin_create_user_only == true
    error_message = "allow_self_signup = false should disable public signup pool-wide."
  }
}

run "custom_css_overrides_the_built_in_default" {
  command = plan

  variables {
    css = ".custom { color: red; }"
  }

  assert {
    condition     = aws_cognito_user_pool_ui_customization.this.css == ".custom { color: red; }"
    error_message = "Custom css should override the built-in default."
  }
}

run "default_css_is_applied_when_none_is_supplied" {
  command = plan

  assert {
    condition     = length(aws_cognito_user_pool_ui_customization.this.css) > 0
    error_message = "A non-empty default css should be applied when none is supplied."
  }
}

run "consumer_clients_map_produces_matching_clients_plus_the_admin_panel_client" {
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
    condition     = length(aws_cognito_user_pool_client.admin_panel) == 1
    error_message = "The admin panel's own client should always be created when create_admin_panel is true (the default)."
  }
}

run "admin_panel_client_is_omitted_when_admin_panel_is_disabled" {
  command = plan

  variables {
    create_admin_panel = false
  }

  assert {
    condition     = length(aws_cognito_user_pool_client.admin_panel) == 0
    error_message = "The admin panel client should not be created when create_admin_panel is false."
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
