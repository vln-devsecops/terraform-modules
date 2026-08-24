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

  # Required whenever auth_profile provisions the public auth API (the
  # default, "full") -- see the ses_configuration_required_for_public_auth_api
  # check block.
  ses_configuration = {
    configuration_set_name = "cfgset"
    source_arn             = "arn:aws:ses:us-east-1:123456789012:identity/example.com"
    from_email_address     = "no-reply@example.com"
  }
}

run "spa_is_deployed_and_configured_by_terraform_when_admin_panel_enabled" {
  command = plan

  # The SPA is delivered by Terraform (install + config + sync), not a separate
  # deploy script, so a single apply yields a working site.
  assert {
    condition     = length(null_resource.auth_site_package) == 1
    error_message = "The auth-site package should be installed at apply time when auth_profile is \"full\"."
  }

  assert {
    condition     = length(null_resource.auth_site_deploy) == 1
    error_message = "The auth-site sync/deploy step should run when auth_profile is \"full\"."
  }
}

run "config_json_carries_the_client_id_and_single_tenant_flag" {
  command = plan

  assert {
    condition     = length(local_file.auth_site_config) == 1
    error_message = "config.json should be written by Terraform when auth_profile is \"full\"."
  }

  assert {
    condition     = jsondecode(local_file.auth_site_config[0].content).userPoolClientId == "clientidplaceholder"
    error_message = "config.json should carry the auth-site Cognito app client id."
  }

  assert {
    condition     = jsondecode(local_file.auth_site_config[0].content).multiTenant == false
    error_message = "config.json multiTenant should be false in the default single-tenant mode."
  }

  assert {
    condition     = jsondecode(local_file.auth_site_config[0].content).adminEnabled == true
    error_message = "config.json adminEnabled should be true when auth_profile is \"full\"."
  }
}

run "config_json_multi_tenant_flag_follows_tenancy_mode" {
  command = plan

  variables {
    tenancy_mode = "multi"
  }

  assert {
    condition     = jsondecode(local_file.auth_site_config[0].content).multiTenant == true
    error_message = "config.json multiTenant should be true when tenancy_mode is \"multi\"."
  }
}

run "spa_is_still_deployed_with_admin_disabled_in_its_config_for_the_auth_api_profile" {
  command = plan

  # The SPA bundle itself still serves the login screens in this profile --
  # only its config tells it there's no admin backend to call, rather than a
  # separate placeholder page. See node-vlinder-auth's config.ts/admin-main.ts.
  variables {
    auth_profile = "auth_api"
  }

  assert {
    condition     = length(null_resource.auth_site_deploy) == 1
    error_message = "The SPA deploy step should still run in the auth_api profile -- it serves the login screens."
  }

  assert {
    condition     = jsondecode(local_file.auth_site_config[0].content).adminEnabled == false
    error_message = "config.json adminEnabled should be false in the auth_api profile, so the SPA can degrade gracefully at /admin."
  }
}

run "no_site_deploy_at_all_for_the_identity_only_profile" {
  command = plan

  variables {
    auth_profile = "identity_only"
  }

  assert {
    condition     = length(null_resource.auth_site_package) == 0
    error_message = "The auth-site package should not be installed in the identity_only profile -- there is no site."
  }

  assert {
    condition     = length(null_resource.auth_site_deploy) == 0
    error_message = "The SPA deploy step should not run in the identity_only profile."
  }

  assert {
    condition     = length(local_file.auth_site_config) == 0
    error_message = "config.json should not be written in the identity_only profile."
  }
}
