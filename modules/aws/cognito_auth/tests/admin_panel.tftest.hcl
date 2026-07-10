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
}

variables {
  app_name               = "myapp"
  deployment_environment = "prod"
  route53_zone_id        = "Z1234567890"
  acm_certificate_arn    = "arn:aws:acm:us-east-1:123456789012:certificate/example"
}

run "admin_panel_is_hosted_via_the_shared_static_site_module_by_default" {
  command = plan

  assert {
    condition     = length(module.admin_panel_site) == 1
    error_message = "The admin panel should be hosted via the shared static_site module when create_admin_panel is true (the default)."
  }

  assert {
    condition     = module.admin_panel_site[0].site_name == "admin-devsecops.vlinder.ca"
    error_message = "The admin panel hostname should use the admin_panel_domain_prefix default over the zone's base domain."
  }
}

run "admin_panel_hosting_is_omitted_when_disabled" {
  command = plan

  variables {
    create_admin_panel = false
  }

  assert {
    condition     = length(module.admin_panel_site) == 0
    error_message = "Admin panel hosting should not be provisioned when create_admin_panel is false."
  }
}

run "custom_admin_panel_domain_prefix_is_honored" {
  command = plan

  variables {
    admin_panel_domain_prefix = "console"
  }

  assert {
    condition     = module.admin_panel_site[0].site_name == "console-devsecops.vlinder.ca"
    error_message = "Custom admin_panel_domain_prefix should be honored."
  }
}
