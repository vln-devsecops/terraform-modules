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
}

variables {
  app_name               = "myapp"
  deployment_environment = "prod"
  route53_zone_id        = "Z1234567890"
  acm_certificate_arn    = "arn:aws:acm:us-east-1:123456789012:certificate/example"
}

run "three_lambda_functions_are_created_with_the_expected_runtime" {
  command = plan

  assert {
    condition = (
      aws_lambda_function.post_confirmation.runtime == "nodejs22.x" &&
      aws_lambda_function.pre_token_generation.runtime == "nodejs22.x" &&
      aws_lambda_function.admin_api.runtime == "nodejs22.x"
    )
    error_message = "All three vendored Lambdas should run on nodejs22.x."
  }

  assert {
    condition     = aws_lambda_function.post_confirmation.handler == "index.handler"
    error_message = "Handler entrypoint should match the vendored index.js contract."
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
    condition     = strcontains(aws_iam_role_policy.post_confirmation.policy, "cognito-idp:AdminAddUserToGroup")
    error_message = "post_confirmation's role should be able to add users to groups."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.post_confirmation.policy, "dynamodb:PutItem")
    error_message = "post_confirmation's role should be able to write role assignments."
  }
}

run "admin_api_role_can_manage_users_and_read_roles" {
  command = plan

  assert {
    condition     = strcontains(aws_iam_role_policy.admin_api.policy, "cognito-idp:AdminDisableUser")
    error_message = "admin_api's role should be able to disable/enable users."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.admin_api.policy, "dynamodb:Scan")
    error_message = "admin_api's role should be able to scan the role-assignments/roles tables for cross-tenant listing."
  }
}
