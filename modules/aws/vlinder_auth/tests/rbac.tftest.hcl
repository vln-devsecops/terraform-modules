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

  # Required whenever auth_profile provisions the public auth API (the
  # default, "full") -- see the ses_configuration_required_for_public_auth_api
  # check block.
  ses_configuration = {
    configuration_set_name = "cfgset"
    source_arn             = "arn:aws:ses:us-east-1:123456789012:identity/example.com"
    from_email_address     = "no-reply@example.com"
  }
}

run "default_role_catalog_is_seeded" {
  command = plan

  assert {
    condition     = length(aws_dynamodb_table_item.roles) == 2
    error_message = "The default role catalog (member, admin) should seed two role items."
  }

  assert {
    condition     = jsondecode(aws_dynamodb_table_item.roles["admin"].item).privileges.L[0].S == "admin:users:read:own"
    error_message = "The admin role's privileges should be seeded verbatim."
  }
}

run "custom_role_catalog_overrides_the_default" {
  command = plan

  variables {
    roles = {
      viewer = {
        privileges   = ["reports:read:own"]
        tenant_scope = "tenant"
      }
      super_admin = {
        privileges   = ["admin:users:read:*", "admin:users:write:*", "admin:roles:read"]
        tenant_scope = "global"
      }
    }
    default_role_id = "viewer"
  }

  assert {
    condition     = length(aws_dynamodb_table_item.roles) == 2
    error_message = "Custom roles should replace, not add to, the default catalog."
  }

  assert {
    condition     = jsondecode(aws_dynamodb_table_item.roles["super_admin"].item).tenantScope.S == "global"
    error_message = "tenant_scope should round-trip into the seeded item."
  }
}

run "single_tenant_mode_seeds_exactly_one_default_tenant" {
  command = plan

  assert {
    condition     = length(aws_dynamodb_table_item.tenants) == 1
    error_message = "Single-tenant mode (the default) should seed exactly one implicit tenant."
  }

  assert {
    condition     = jsondecode(aws_dynamodb_table_item.tenants["default"].item).tenantId.S == "default"
    error_message = "The implicit single-tenant record should use the constant tenantId \"default\"."
  }
}

run "multi_tenant_mode_seeds_from_the_tenants_map" {
  command = plan

  variables {
    tenancy_mode = "multi"
    tenants = {
      acme-corp = {
        name         = "Acme Corp"
        email_domain = "acme.com"
      }
      globex = {
        name         = "Globex"
        email_domain = "globex.com"
      }
    }
  }

  assert {
    condition     = length(aws_dynamodb_table_item.tenants) == 2
    error_message = "Multi-tenant mode should seed one item per entry in var.tenants."
  }

  assert {
    condition     = jsondecode(aws_dynamodb_table_item.tenants["acme-corp"].item).emailDomain.S == "acme.com"
    error_message = "email_domain should round-trip into the seeded tenant item."
  }
}

run "user_role_assignments_table_is_composed_from_the_shared_dynamodb_module" {
  command = plan

  assert {
    condition     = length(module.user_role_assignments.table_name) > 0
    error_message = "The user_role_assignments table should be provisioned via the shared aws/dynamodb module."
  }
}
