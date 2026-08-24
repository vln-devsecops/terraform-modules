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

  # The Lambda IAM policies interpolate CMK ARNs (table encryption keys);
  # without a plan-time default the whole jsonencoded policy string becomes
  # unknown and the strcontains assertions below can't evaluate.
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

run "five_lambda_functions_are_created_with_the_expected_runtime" {
  command = plan

  assert {
    condition = (
      aws_lambda_function.pre_sign_up.runtime == "nodejs22.x" &&
      aws_lambda_function.post_confirmation.runtime == "nodejs22.x" &&
      aws_lambda_function.pre_token_generation.runtime == "nodejs22.x" &&
      aws_lambda_function.admin_api[0].runtime == "nodejs22.x" &&
      aws_lambda_function.auth_api[0].runtime == "nodejs22.x"
    )
    error_message = "All five Lambdas should run on nodejs22.x."
  }
}

run "pre_sign_up_lambda_is_wired_into_lambda_config_with_no_extra_permissions" {
  command = plan

  assert {
    condition     = one(aws_cognito_user_pool.this.lambda_config).pre_sign_up == aws_lambda_function.pre_sign_up.arn
    error_message = "pre_sign_up should be wired into the user pool's lambda_config."
  }

  assert {
    condition     = aws_lambda_function.pre_sign_up.handler == "pre-sign-up/handler.handler"
    error_message = "pre_sign_up handler must be 'pre-sign-up/handler.handler' to match dist layout."
  }

  assert {
    condition     = length(aws_lambda_function.pre_sign_up.environment) == 0
    error_message = "pre_sign_up should carry no environment variables -- it's a pure stateless auto-confirm trigger, unlike the other Cognito trigger Lambdas."
  }
}

run "lambda_handler_paths_match_dist_layout" {
  command = plan

  # The package builds to dist/{pre-sign-up,post-confirmation,pre-token-generation,admin-api,shared}/
  # handler.js in each subdirectory. The shared/ directory sits at the zip root
  # (dist/ is zipped whole), so all three handlers can resolve ../shared/* at
  # runtime. Handler = "<subdir>/<file-without-ext>.<exported-fn>".
  assert {
    condition     = aws_lambda_function.post_confirmation.handler == "post-confirmation/handler.handler"
    error_message = "post_confirmation handler must be 'post-confirmation/handler.handler' to match dist layout."
  }

  assert {
    condition     = aws_lambda_function.pre_token_generation.handler == "pre-token-generation/handler.handler"
    error_message = "pre_token_generation handler must be 'pre-token-generation/handler.handler' to match dist layout."
  }

  assert {
    condition     = aws_lambda_function.admin_api[0].handler == "admin-api/handler.handler"
    error_message = "admin_api handler must be 'admin-api/handler.handler' to match dist layout."
  }
}

run "all_five_lambdas_share_the_same_zip" {
  command = plan

  # One zip for the full dist/ tree (shared/ present at root) rather than
  # per-handler zips (which would leave shared/ out of each package).
  assert {
    condition     = aws_lambda_function.pre_sign_up.filename == aws_lambda_function.post_confirmation.filename
    error_message = "pre_sign_up must share the same zip as the other Lambdas so dist/shared/ is available."
  }

  assert {
    condition     = aws_lambda_function.post_confirmation.filename == aws_lambda_function.pre_token_generation.filename
    error_message = "post_confirmation and pre_token_generation must share one zip so dist/shared/ is available to both."
  }

  assert {
    condition     = aws_lambda_function.post_confirmation.filename == aws_lambda_function.admin_api[0].filename
    error_message = "admin_api must share the same zip as the trigger Lambdas so dist/shared/ is available."
  }

  assert {
    condition     = aws_lambda_function.post_confirmation.filename == aws_lambda_function.auth_api[0].filename
    error_message = "auth_api must share the same zip as the trigger Lambdas so dist/shared/ is available."
  }
}

run "post_confirmation_env_vars_match_the_vendored_lambda_contract" {
  command = plan

  assert {
    condition = (
      one(aws_lambda_function.post_confirmation.environment).variables["TENANCY_MODE"] == "single" &&
      one(aws_lambda_function.post_confirmation.environment).variables["DEFAULT_TENANT_ID"] == "default" &&
      one(aws_lambda_function.post_confirmation.environment).variables["DEFAULT_ROLE_ID"] == "member" &&
      one(aws_lambda_function.post_confirmation.environment).variables["TENANTS_TABLE_NAME"] == aws_dynamodb_table.tenants.name &&
      one(aws_lambda_function.post_confirmation.environment).variables["ROLE_ASSIGNMENTS_TABLE_NAME"] == module.user_role_assignments.table_name
    )
    error_message = "post_confirmation environment variables should match lambda-src's expected config keys."
  }

  assert {
    condition     = !contains(keys(one(aws_lambda_function.post_confirmation.environment).variables), "USER_POOL_ID")
    error_message = "post_confirmation must not depend on a USER_POOL_ID env var -- Cognito supplies userPoolId on the trigger event itself, and requiring it here would create a circular dependency with the pool's lambda_config."
  }
}

run "baseline_groups_env_var_is_a_comma_joined_list" {
  command = plan

  variables {
    groups = {
      staff = { description = "Staff", precedence = 5 }
    }
    baseline_groups = ["staff"]
  }

  assert {
    condition     = one(aws_lambda_function.post_confirmation.environment).variables["BASELINE_GROUPS"] == "staff"
    error_message = "baseline_groups should be joined into a single comma-separated env var."
  }
}

run "pre_token_generation_env_vars_match_the_vendored_lambda_contract" {
  command = plan

  assert {
    condition = (
      one(aws_lambda_function.pre_token_generation.environment).variables["ROLE_ASSIGNMENTS_TABLE_NAME"] == module.user_role_assignments.table_name &&
      one(aws_lambda_function.pre_token_generation.environment).variables["ROLES_TABLE_NAME"] == aws_dynamodb_table.roles.name
    )
    error_message = "pre_token_generation environment variables should match lambda-src's expected config keys."
  }
}

run "lambda_config_wires_both_triggers_onto_the_user_pool" {
  command = plan

  assert {
    condition     = one(aws_cognito_user_pool.this.lambda_config).post_confirmation == aws_lambda_function.post_confirmation.arn
    error_message = "post_confirmation should be wired into the user pool's lambda_config."
  }

  assert {
    condition     = one(one(aws_cognito_user_pool.this.lambda_config).pre_token_generation_config).lambda_arn == aws_lambda_function.pre_token_generation.arn
    error_message = "pre_token_generation should be wired into the user pool's lambda_config."
  }
}

run "post_confirmation_role_can_write_role_assignments_and_manage_groups" {
  command = plan

  assert {
    condition     = strcontains(aws_iam_policy.post_confirmation.policy, "cognito-idp:AdminAddUserToGroup")
    error_message = "post_confirmation's role should be able to add users to groups."
  }

  assert {
    condition     = strcontains(aws_iam_policy.post_confirmation.policy, "dynamodb:PutItem")
    error_message = "post_confirmation's role should be able to write role assignments."
  }
}

run "admin_api_role_can_manage_users_and_read_roles" {
  command = plan

  assert {
    condition     = strcontains(aws_iam_policy.admin_api[0].policy, "cognito-idp:AdminDisableUser")
    error_message = "admin_api's role should be able to disable/enable users."
  }

  assert {
    condition     = strcontains(aws_iam_policy.admin_api[0].policy, "dynamodb:Scan")
    error_message = "admin_api's role should be able to scan the role-assignments/roles tables for cross-tenant listing."
  }
}

run "all_lambda_roles_can_use_the_table_encryption_keys" {
  command = plan

  # Every table is CMK-encrypted and DynamoDB requires the caller to hold
  # KMS permissions on the table's key -- a table-arn grant alone fails at
  # runtime with kms:Decrypt AccessDeniedException on the first real
  # invocation, which is exactly how this was originally caught (by the
  # live e2e suite; no plan-time check can see it).
  assert {
    condition     = strcontains(aws_iam_policy.pre_token_generation.policy, "kms:Decrypt")
    error_message = "pre_token_generation must be able to decrypt the CMK-encrypted tables it reads."
  }

  assert {
    condition     = strcontains(aws_iam_policy.post_confirmation.policy, "kms:Decrypt")
    error_message = "post_confirmation must be able to use the CMKs of the tables it reads/writes."
  }

  assert {
    condition     = strcontains(aws_iam_policy.admin_api[0].policy, "kms:Decrypt")
    error_message = "admin_api must be able to use the CMKs of the tables it reads/writes."
  }
}
