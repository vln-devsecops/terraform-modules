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
    condition     = jsondecode(aws_dynamodb_table_item.roles["admin"].item).privileges.L[0].S == "read:admin/users"
    error_message = "The admin role's privileges should be seeded verbatim."
  }
}

run "custom_role_catalog_overrides_the_default" {
  command = plan

  variables {
    roles = {
      viewer = {
        privileges   = ["read:reports"]
        tenant_scope = "tenant"
      }
      super_admin = {
        privileges   = ["read:*:admin/users", "write:*:admin/users", "read:admin/roles"]
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
    # The implicit "default" tenant, plus the auth application's own reserved
    # "auth" tenant -- present in every deployment, not just multi-tenant
    # ones, so auth.<zone> reached without a client_id still resolves.
    condition     = length(aws_dynamodb_table_item.tenants) == 2
    error_message = "Single-tenant mode (the default) should seed the implicit tenant plus the auth application's own tenant."
  }

  assert {
    condition     = jsondecode(aws_dynamodb_table_item.tenants["default"].item).tenantId.S == "default"
    error_message = "The implicit single-tenant record should use the constant tenantId \"default\"."
  }

  assert {
    condition     = jsondecode(aws_dynamodb_table_item.tenants["auth"].item).tenantId.S == "auth"
    error_message = "The auth application's own tenant should always be seeded, using the reserved tenantId \"auth\"."
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
    # var.tenants' two entries, plus the always-present "auth" tenant.
    condition     = length(aws_dynamodb_table_item.tenants) == 3
    error_message = "Multi-tenant mode should seed one item per entry in var.tenants, plus the auth application's own tenant."
  }

  assert {
    condition     = jsondecode(aws_dynamodb_table_item.tenants["acme-corp"].item).emailDomain.S == "acme.com"
    error_message = "email_domain should round-trip into the seeded tenant item."
  }
}

run "tenants_table_key_schema_supports_multiple_record_types_per_tenant" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.tenants.hash_key == "tenantId" && aws_dynamodb_table.tenants.range_key == "sk"
    error_message = "The tenants table needs a range key to hold more than the profile record per tenant (client and domain-provider registrations)."
  }

  assert {
    condition     = jsondecode(aws_dynamodb_table_item.tenants["default"].item).sk.S == "PROFILE"
    error_message = "The tenant's own record should be the \"PROFILE\" item."
  }
}

run "client_registered_to_a_tenant_is_looked_up_via_the_client_id_index" {
  command = plan

  variables {
    tenancy_mode = "multi"
    tenants = {
      acme-corp = { name = "Acme Corp" }
    }
    clients = {
      web = {
        callback_urls = ["https://app.example.com/callback"]
        logout_urls   = ["https://app.example.com/logout"]
        tenant_id     = "acme-corp"
      }
    }
  }

  assert {
    condition     = jsondecode(aws_dynamodb_table_item.tenant_clients["web"].item).tenantId.S == "acme-corp"
    error_message = "A client's CLIENT# registry item should carry the tenant_id it was assigned."
  }

  assert {
    condition     = one([for gsi in aws_dynamodb_table.tenants.global_secondary_index : gsi if gsi.name == "clientId-index"]) != null
    error_message = "The tenants table needs a clientId-index GSI: the tenant isn't known yet when resolving from client_id."
  }
}

run "auth_site_own_client_is_registered_under_the_reserved_auth_tenant" {
  command = plan

  assert {
    condition     = jsondecode(aws_dynamodb_table_item.auth_site_tenant_client[0].item).tenantId.S == "auth"
    error_message = "auth_site's own Cognito client should be registered under the reserved \"auth\" tenant."
  }
}

run "domain_pinned_to_an_identity_provider_is_seeded_under_its_tenant" {
  command = plan

  variables {
    tenancy_mode = "multi"
    tenants = {
      acme-corp = {
        name = "Acme Corp"
        identity_providers = {
          "acme.com" = "okta-acme"
        }
      }
    }
  }

  assert {
    condition     = jsondecode(aws_dynamodb_table_item.tenant_domain_providers["acme-corp#acme.com"].item).identityProviderId.S == "okta-acme"
    error_message = "A tenant's identity_providers entry should seed a DOMAIN# item carrying the pinned provider id."
  }

  assert {
    condition     = jsondecode(aws_dynamodb_table_item.tenant_domain_providers["acme-corp#acme.com"].item).sk.S == "DOMAIN#acme.com"
    error_message = "The domain-provider pin should be keyed \"DOMAIN#<domain>\" under the owning tenant."
  }
}

run "user_role_assignments_table_is_composed_from_the_shared_dynamodb_module" {
  command = plan

  assert {
    condition     = length(module.user_role_assignments.table_name) > 0
    error_message = "The user_role_assignments table should be provisioned via the shared aws/dynamodb module."
  }
}
