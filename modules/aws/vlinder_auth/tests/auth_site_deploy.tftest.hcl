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

  assert {
    condition     = length(local_file.auth_site_discovery_document) == 0
    error_message = "The OIDC discovery document should not be written in the identity_only profile -- there is no site to serve it from."
  }
}

run "discovery_document_is_written_to_the_well_known_path" {
  command = plan

  assert {
    condition     = length(local_file.auth_site_discovery_document) == 1
    error_message = "The OIDC discovery document should be written by Terraform when auth_profile is \"full\"."
  }

  assert {
    condition     = local_file.auth_site_discovery_document[0].filename == "${local.auth_site_dist_dir}/.well-known/openid-configuration"
    error_message = "The discovery document must be served at the standard /.well-known/openid-configuration path."
  }
}

run "discovery_document_issuer_and_jwks_uri_come_straight_from_cognito" {
  command = plan

  # No mirroring: issuer/jwks_uri name Cognito's real endpoints directly, so
  # key rotation is never served stale. Both must derive from this module's
  # own user pool, mirroring identity.tftest.hcl's issuer_url assertions.
  assert {
    condition     = local_file.auth_site_discovery_document[0].content == local.auth_site_discovery_document_json
    error_message = "The discovery document's content should come from local.auth_site_discovery_document_json, not be constructed separately."
  }

  assert {
    condition     = jsondecode(local_file.auth_site_discovery_document[0].content).issuer == local.admin_api_issuer_url
    error_message = "The discovery document's issuer must be this module's own user pool issuer URL -- the same one the admin API's JWT authorizer trusts."
  }

  assert {
    condition     = strcontains(jsondecode(local_file.auth_site_discovery_document[0].content).issuer, aws_cognito_user_pool.this.id)
    error_message = "issuer must be derived from this module's own user pool."
  }

  assert {
    condition     = jsondecode(local_file.auth_site_discovery_document[0].content).jwks_uri == "${local.admin_api_issuer_url}/.well-known/jwks.json"
    error_message = "jwks_uri must resolve against Cognito's own issuer, not a mirrored/rehosted key set."
  }
}

run "discovery_document_publishes_first_party_endpoint_urls" {
  command = plan

  # These name routes that don't have a live handler yet (plan.md step 6 --
  # RP handoff: /authorize + /token -- is still unbuilt), which is fine:
  # publishing the URL is independent of the endpoint existing yet, same as
  # identify.ts's /federation location before step 11 builds it.
  assert {
    condition     = jsondecode(local_file.auth_site_discovery_document[0].content).authorization_endpoint == "https://${local.auth_site_domain}/api/v1/auth/authorize"
    error_message = "authorization_endpoint should be first-party, under this deployment's own auth site domain."
  }

  assert {
    condition     = jsondecode(local_file.auth_site_discovery_document[0].content).token_endpoint == "https://${local.auth_site_domain}/api/v1/auth/token"
    error_message = "token_endpoint should be first-party, under this deployment's own auth site domain."
  }

  assert {
    condition     = jsondecode(local_file.auth_site_discovery_document[0].content).end_session_endpoint == "https://${local.auth_site_domain}/api/v1/auth/logout"
    error_message = "end_session_endpoint should be first-party, under this deployment's own auth site domain."
  }
}

run "discovery_document_carries_the_oidc_required_metadata" {
  command = plan

  # response_types_supported/subject_types_supported/
  # id_token_signing_alg_values_supported are REQUIRED members of an OIDC
  # discovery document per OpenID Connect Discovery 1.0 -- distinct from the
  # already-acknowledged issuer/host-mismatch deviation. Values reflect what
  # Cognito actually does.
  assert {
    condition     = tolist(jsondecode(local_file.auth_site_discovery_document[0].content).response_types_supported) == tolist(["code"])
    error_message = "response_types_supported must be published (REQUIRED by OIDC Discovery 1.0) and reflect Cognito's authorization code flow."
  }

  assert {
    condition     = tolist(jsondecode(local_file.auth_site_discovery_document[0].content).subject_types_supported) == tolist(["public"])
    error_message = "subject_types_supported must be published (REQUIRED by OIDC Discovery 1.0) -- Cognito uses public, not pairwise, subject identifiers."
  }

  assert {
    condition     = tolist(jsondecode(local_file.auth_site_discovery_document[0].content).id_token_signing_alg_values_supported) == tolist(["RS256"])
    error_message = "id_token_signing_alg_values_supported must be published (REQUIRED by OIDC Discovery 1.0) -- Cognito signs with RS256."
  }
}

run "discovery_document_deploy_redeploys_on_content_change" {
  command = plan

  assert {
    condition     = one(null_resource.auth_site_deploy[*].triggers)["discovery_document"] == local.auth_site_discovery_document_json
    error_message = "The SPA deploy step should re-sync when the discovery document's content changes, same as it does for config.json."
  }
}

run "spa_viewer_request_does_not_rewrite_well_known_paths" {
  command = plan

  # Without this exemption, /.well-known/openid-configuration (extensionless
  # by specification) fails the static-asset check and gets silently
  # rewritten to /index.html with a 200 -- a failure that looks like success
  # to every consumer.
  assert {
    condition     = strcontains(aws_cloudfront_function.spa_viewer_request[0].code, ".well-known")
    error_message = "spa_viewer_request must exempt /.well-known/* from the SPA fallback rewrite."
  }
}

run "default_behavior_response_headers_policy_is_cors_open" {
  command = plan

  # The discovery document must be fetchable cross-origin (a resource
  # server on a different origin needs to read it to learn what issuer/keys
  # to trust). CloudFront response-headers policies apply per-behavior, not
  # per-path, so this is asserted at the policy level.
  assert {
    condition = (
      one(aws_cloudfront_response_headers_policy.auth_site_default[*].cors_config)[0].access_control_allow_origins[0].items == toset(["*"])
      && one(aws_cloudfront_response_headers_policy.auth_site_default[*].cors_config)[0].origin_override == true
    )
    error_message = "The default behavior's response-headers policy should be CORS-open (Access-Control-Allow-Origin: *) so the discovery document is fetchable cross-origin."
  }
}
