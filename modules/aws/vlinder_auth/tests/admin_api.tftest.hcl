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

  # auth_api's and rotate_secret's own IAM policies interpolate this secret's
  # ARN; without a plan-time default the whole jsonencoded policy string
  # becomes unknown and the strcontains assertions below can't evaluate.
  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:placeholder"
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

  # The claims the authorizer forwards are exactly what admin-api/authz.ts's
  # extractCallerContext reads: "tenants" (space-delimited authenticated
  # tenants) and "scope" (space-delimited privileges). Forwarding the wrong
  # names here is silent and total: extractCallerContext falls back to an
  # empty list for anything not forwarded, so every tenant-scoped admin
  # action 403s with no error pointing at the real cause -- exactly the
  # failure class already hit once with the Terraform-seeded role catalog.
  assert {
    condition     = toset(module.admin_api_authorizer[0].jwt_forward_claims) == toset(["tenants", "scope"])
    error_message = "The admin API authorizer must forward exactly the \"tenants\" and \"scope\" claims -- lambda-src's extractCallerContext reads no others."
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
        "GET /api/v1/users", "GET /api/v1/users/{userId}", "PATCH /api/v1/users/{userId}/enabled",
        "GET /api/v1/roles", "PUT /api/v1/users/{userId}/roles/{roleId}", "DELETE /api/v1/users/{userId}/roles/{roleId}",
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

run "admin_api_csrf_secret_is_provisioned_and_wired_to_auth_api" {
  command = plan

  # The file-level aws_secretsmanager_secret mock above gives every secret
  # the *same* placeholder ARN, so strcontains(..., one(admin_api_csrf_secret
  # [*].arn)) would pass even if ADMIN_API_CSRF_SECRET_ID pointed at a
  # different secret entirely -- all four ARNs are identical strings without
  # this override. Give this one secret a distinct ARN so the assertions
  # below actually exercise which secret auth_api is wired to, not merely
  # that *some* secret's ARN appears in the policy/env var.
  override_resource {
    target          = aws_secretsmanager_secret.admin_api_csrf_secret[0]
    override_during = plan
    values = {
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:admin-api-csrf-secret-distinct"
    }
  }

  # See doc/admin-api-csrf.md: this secret is the shared HMAC key behind the
  # vln_auth_csrf double-submit cookie. auth_api mints it (needs
  # GetSecretValue); admin_api_rewrite.js's own check never reads the secret
  # itself, only compares a header to a cookie already on the request.
  assert {
    condition     = length(aws_secretsmanager_secret.admin_api_csrf_secret) == 1
    error_message = "The admin API CSRF secret should be provisioned whenever the public auth API is (same count gate as the other auth secrets)."
  }

  assert {
    condition     = strcontains(aws_iam_policy.auth_api[0].policy, one(aws_secretsmanager_secret.admin_api_csrf_secret[*].arn))
    error_message = "auth_api's role should be able to GetSecretValue on the admin-api CSRF secret -- it mints the vln_auth_csrf cookie's HMAC value."
  }

  assert {
    condition     = strcontains(aws_iam_policy.rotate_secret[0].policy, one(aws_secretsmanager_secret.admin_api_csrf_secret[*].arn))
    error_message = "rotate_secret's role should be able to PutSecretValue on the admin-api CSRF secret, same as the module's other rotatable auth secrets."
  }

  assert {
    condition     = one(aws_lambda_function.auth_api[0].environment).variables["ADMIN_API_CSRF_SECRET_ID"] == one(aws_secretsmanager_secret.admin_api_csrf_secret[*].arn)
    error_message = "auth_api's ADMIN_API_CSRF_SECRET_ID env var should point at the admin-api CSRF secret, matching node-vlinder-auth's cookie-minting side."
  }

  assert {
    condition     = length(aws_scheduler_schedule.rotate_admin_api_csrf_secret) == 1
    error_message = "The admin API CSRF secret should be on the same recurring rotation schedule as the module's other auth secrets."
  }
}

run "admin_api_rewrite_enforces_double_submit_csrf" {
  command = plan

  # strcontains against the compiled CloudFront Function source is this
  # repo's established way of asserting on function *logic* -- see
  # no_api_cloudfront_function_rewrites_a_uri in tests/admin_panel.tftest.hcl
  # for the pattern. terraform test can't execute the function's JS runtime,
  # so this is necessarily best-effort: it confirms the check's building
  # blocks are present in the compiled code, not that the runtime behavior is
  # correct end to end (see the standalone Node verification script run
  # separately for that).
  assert {
    condition     = strcontains(aws_cloudfront_function.admin_api_rewrite[0].code, "vln_auth_csrf")
    error_message = "admin_api_rewrite.js should read the vln_auth_csrf cookie as part of its double-submit CSRF check."
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.admin_api_rewrite[0].code, "x-vln-csrf-token")
    error_message = "admin_api_rewrite.js should read the x-vln-csrf-token header as part of its double-submit CSRF check."
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.admin_api_rewrite[0].code, "403")
    error_message = "admin_api_rewrite.js should reject a failed CSRF check with a 403 response."
  }
}

run "admin_api_rewrite_avoids_syntax_cloudfront_js_2_0_rejects" {
  command = plan

  # Real regression, not a hypothetical: admin_api_rewrite.js once shipped
  # with `?.` (optional chaining), and `aws cloudfront test-function` against
  # the actually-deployed function proved cloudfront-js-2.0's parser rejects
  # it outright (SyntaxError). CloudFront then serves its own generic 503
  # HTML page for *every* request through the /api/v1/* behavior, before the
  # request ever reaches the origin -- no Lambda invocation, no CloudWatch
  # log, nothing but a silent, 100%-reproducible admin-panel failure.
  #
  # The guarantee this asserts on no longer comes from a developer manually
  # avoiding the syntax in source: templates/src/admin_api_rewrite.js is free
  # to use `?.`/`??` (and does), because `code` above reads
  # templates/dist/admin_api_rewrite.js, generated from src/ by
  # edge-functions-build/ (esbuild targeting es2019, which downlevels both
  # operators into cloudfront-js-2.0-compatible code) -- see
  # doc/cloudfront-js-runtime-compatibility.md. This assertion is kept as a
  # second, independent layer of defense-in-depth: it protects against
  # someone bypassing the build system altogether, e.g. hand-editing dist/
  # directly, which the ci_terraform.yml `git diff --exit-code` freshness
  # check also catches independently. terraform test's mock provider can't
  # execute this function's JS runtime (see the comment above
  # admin_api_rewrite_enforces_double_submit_csrf), so this can only ever be
  # a static guard against syntax already known to be unsupported -- not a
  # substitute for occasionally re-running `aws cloudfront test-function`
  # against the real deployed function.
  assert {
    condition     = !can(regex("\\?\\.", aws_cloudfront_function.admin_api_rewrite[0].code))
    error_message = "admin_api_rewrite.js's compiled output must not contain optional chaining (?.) -- cloudfront-js-2.0 rejects it with a SyntaxError. If templates/src changed, rebuild via `npm run build` in edge-functions-build/; if dist/ was hand-edited, regenerate it instead."
  }

  assert {
    condition     = !can(regex("\\?\\?", aws_cloudfront_function.admin_api_rewrite[0].code))
    error_message = "admin_api_rewrite.js's compiled output must not contain the nullish-coalescing operator (??) -- unconfirmed whether cloudfront-js-2.0 supports it, and not worth risking the same failure mode as ?. for a convenience operator."
  }
}
