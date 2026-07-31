mock_provider "aws" {
  override_during = plan

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

  mock_resource "aws_lambda_function" {
    defaults = {
      arn = "arn:aws:lambda:us-east-1:123456789012:function:placeholder"
    }
  }

  mock_resource "aws_lambda_function_url" {
    defaults = {
      function_url = "https://placeholder.lambda-url.us-east-1.on.aws/"
    }
  }

  mock_resource "aws_dynamodb_table" {
    defaults = {
      arn = "arn:aws:dynamodb:us-east-1:123456789012:table/placeholder"
    }
  }

  # Lambda IAM policies interpolate CMK ARNs (table + module encryption
  # keys); without a plan-time default the whole jsonencoded policy string
  # becomes unknown and the strcontains assertions below can't evaluate.
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    }
  }

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
}

run "fixed_names_include_a_random_per_stack_suffix" {
  command = plan

  override_resource {
    target          = random_string.unguessable
    override_during = plan
    values = {
      result = "abcd1234"
    }
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/myapp-prod-contact-form-abcd1234"
    error_message = "The KMS alias should include the per-stack random suffix so it never collides with a predecessor still inside its deletion window."
  }

  assert {
    condition     = aws_secretsmanager_secret.recaptcha.name == "myapp-prod-contact-form-recaptcha-secret-abcd1234"
    error_message = "The reCAPTCHA secret should include the per-stack random suffix so it never collides with a predecessor still inside its deletion window."
  }

  assert {
    condition     = aws_iam_role.submit.name == "myapp-prod-contact-form-submit-abcd1234"
    error_message = "The submit IAM role should include the per-stack random suffix."
  }

  assert {
    condition     = aws_iam_role.admin.name == "myapp-prod-contact-form-admin-abcd1234"
    error_message = "The admin IAM role should include the per-stack random suffix."
  }

  assert {
    condition     = aws_iam_policy.submit.name == "myapp-prod-contact-form-submit-abcd1234"
    error_message = "The submit IAM policy should include the per-stack random suffix."
  }

  assert {
    condition     = aws_iam_policy.admin.name == "myapp-prod-contact-form-admin-abcd1234"
    error_message = "The admin IAM policy should include the per-stack random suffix."
  }

  assert {
    condition     = aws_lambda_function.submit.function_name == "myapp-prod-contact-form-submit-abcd1234"
    error_message = "The submit Lambda function should include the per-stack random suffix."
  }

  assert {
    condition     = aws_lambda_function.admin.function_name == "myapp-prod-contact-form-admin-abcd1234"
    error_message = "The admin Lambda function should include the per-stack random suffix."
  }
}

run "a_different_random_draw_produces_non_colliding_names" {
  command = plan

  # Same app_name/deployment_environment as the previous run (two stacks --
  # e.g. concurrent PR previews, or a preview re-applied while a prior
  # destroy's resources are still inside their deletion window), but a
  # different random draw, since each stack's random_string.unguessable is
  # generated independently in its own state. Every fixed name must move
  # with it so the two stacks never collide.
  override_resource {
    target          = random_string.unguessable
    override_during = plan
    values = {
      result = "zyxw9876"
    }
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/myapp-prod-contact-form-zyxw9876"
    error_message = "A different random draw must produce a different KMS alias name."
  }

  assert {
    condition     = aws_secretsmanager_secret.recaptcha.name == "myapp-prod-contact-form-recaptcha-secret-zyxw9876"
    error_message = "A different random draw must produce a different reCAPTCHA secret name."
  }

  assert {
    condition     = aws_iam_role.submit.name == "myapp-prod-contact-form-submit-zyxw9876"
    error_message = "A different random draw must produce a different submit IAM role name."
  }

  assert {
    condition     = aws_iam_role.admin.name == "myapp-prod-contact-form-admin-zyxw9876"
    error_message = "A different random draw must produce a different admin IAM role name."
  }

  assert {
    condition     = aws_iam_policy.submit.name == "myapp-prod-contact-form-submit-zyxw9876"
    error_message = "A different random draw must produce a different submit IAM policy name."
  }

  assert {
    condition     = aws_iam_policy.admin.name == "myapp-prod-contact-form-admin-zyxw9876"
    error_message = "A different random draw must produce a different admin IAM policy name."
  }

  assert {
    condition     = aws_lambda_function.submit.function_name == "myapp-prod-contact-form-submit-zyxw9876"
    error_message = "A different random draw must produce a different submit Lambda function name."
  }

  assert {
    condition     = aws_lambda_function.admin.function_name == "myapp-prod-contact-form-admin-zyxw9876"
    error_message = "A different random draw must produce a different admin Lambda function name."
  }
}

run "both_lambdas_run_on_the_expected_runtime" {
  command = plan

  assert {
    condition     = aws_lambda_function.submit.runtime == "nodejs22.x" && aws_lambda_function.admin.runtime == "nodejs22.x"
    error_message = "Both Lambdas should run on nodejs22.x."
  }
}

run "lambda_handler_paths_match_dist_layout" {
  command = plan

  # The package builds to dist/{submit,admin,shared}/handler.js in each
  # subdirectory. shared/ sits at the zip root (dist/ is zipped whole), so
  # both handlers can resolve ../shared/* at runtime. Handler =
  # "<subdir>/<file-without-ext>.<exported-fn>".
  assert {
    condition     = aws_lambda_function.submit.handler == "submit/handler.handler"
    error_message = "submit handler must be 'submit/handler.handler' to match dist layout."
  }

  assert {
    condition     = aws_lambda_function.admin.handler == "admin/handler.handler"
    error_message = "admin handler must be 'admin/handler.handler' to match dist layout."
  }
}

run "both_lambdas_share_the_same_zip" {
  command = plan

  # One zip for the full dist/ tree (shared/ present at root) rather than
  # per-handler zips, which would leave shared/ out of one of them.
  assert {
    condition     = aws_lambda_function.submit.filename == aws_lambda_function.admin.filename
    error_message = "submit and admin must share one zip so dist/shared/ is available to both."
  }
}

run "submit_function_url_is_public_admin_is_iam_authorized" {
  command = plan

  assert {
    condition     = aws_lambda_function_url.submit.authorization_type == "NONE"
    error_message = "submit's Function URL must be publicly reachable (NONE) -- it's the public entry point."
  }

  assert {
    condition     = aws_lambda_function_url.admin.authorization_type == "AWS_IAM"
    error_message = "admin's Function URL must be AWS_IAM-authorized -- that's this module's entire access-control boundary for admin operations, not app code."
  }
}

run "submit_env_vars_match_the_vendored_lambda_contract" {
  command = plan

  assert {
    condition     = one(aws_lambda_function.submit.environment).variables["CONTACT_FORM_TABLE_NAME"] == module.table.table_name
    error_message = "submit's CONTACT_FORM_TABLE_NAME must match the provisioned table."
  }

  assert {
    condition     = one(aws_lambda_function.submit.environment).variables["RECAPTCHA_SECRET_ARN"] == aws_secretsmanager_secret.recaptcha.arn
    error_message = "submit must be given the reCAPTCHA secret's ARN to verify submissions."
  }
}

run "admin_env_vars_match_the_vendored_lambda_contract_and_exclude_the_recaptcha_secret" {
  command = plan

  assert {
    condition     = one(aws_lambda_function.admin.environment).variables["CONTACT_FORM_TABLE_NAME"] == module.table.table_name
    error_message = "admin's CONTACT_FORM_TABLE_NAME must match the provisioned table."
  }

  assert {
    condition     = !contains(keys(one(aws_lambda_function.admin.environment).variables), "RECAPTCHA_SECRET_ARN")
    error_message = "admin has no reCAPTCHA verification code and should not be given the secret's ARN."
  }
}

run "submit_role_can_write_entries_and_read_the_recaptcha_secret" {
  command = plan

  assert {
    condition     = strcontains(aws_iam_policy.submit.policy, "dynamodb:PutItem")
    error_message = "submit's role should be able to write new entries."
  }

  assert {
    condition     = strcontains(aws_iam_policy.submit.policy, "secretsmanager:GetSecretValue")
    error_message = "submit's role should be able to read the reCAPTCHA secret."
  }

  assert {
    condition     = !strcontains(aws_iam_policy.submit.policy, "dynamodb:DeleteItem")
    error_message = "submit's role should not be able to delete entries -- that's an admin-only operation."
  }
}

run "admin_role_can_query_and_delete_but_not_write" {
  command = plan

  assert {
    condition     = strcontains(aws_iam_policy.admin.policy, "dynamodb:Query")
    error_message = "admin's role should be able to list/get entries via Query."
  }

  assert {
    condition     = strcontains(aws_iam_policy.admin.policy, "dynamodb:DeleteItem")
    error_message = "admin's role should be able to delete entries."
  }

  assert {
    condition     = !strcontains(aws_iam_policy.admin.policy, "dynamodb:PutItem")
    error_message = "admin's role should not be able to write new entries -- that's the public submit path's job."
  }
}

run "both_lambda_roles_can_use_the_table_encryption_key" {
  command = plan

  # DynamoDB requires the caller to hold KMS permissions on the table's own
  # key -- a table-arn grant alone fails at runtime with a kms:Decrypt
  # AccessDeniedException on first invocation, not at plan time.
  assert {
    condition     = strcontains(aws_iam_policy.submit.policy, "kms:Decrypt")
    error_message = "submit must be able to use the table's CMK to write encrypted items."
  }

  assert {
    condition     = strcontains(aws_iam_policy.admin.policy, "kms:Decrypt")
    error_message = "admin must be able to use the table's CMK to read/delete encrypted items."
  }
}

run "no_admin_invoke_grants_without_allowed_principals" {
  command = plan

  assert {
    condition     = length(aws_lambda_permission.admin_invoke) == 0
    error_message = "No lambda:InvokeFunctionUrl grants should exist when admin_allowed_principal_arns is empty -- AWS_IAM auth alone grants no one access."
  }
}

run "admin_invoke_grants_exactly_the_listed_principals" {
  command = plan

  variables {
    admin_allowed_principal_arns = [
      "arn:aws:iam::123456789012:user/ronald",
      "arn:aws:iam::123456789012:role/ops",
    ]
  }

  assert {
    condition     = length(aws_lambda_permission.admin_invoke) == 2
    error_message = "Exactly one grant should be created per listed principal."
  }

  assert {
    condition = alltrue([
      for grant in aws_lambda_permission.admin_invoke :
      grant.action == "lambda:InvokeFunctionUrl" && grant.function_url_auth_type == "AWS_IAM"
    ])
    error_message = "Every grant must be scoped to lambda:InvokeFunctionUrl under AWS_IAM auth, not a broader lambda:InvokeFunction grant."
  }
}

run "submit_cors_is_applied_to_the_public_function_url_only" {
  command = plan

  variables {
    submit_cors = {
      allow_methods = ["POST"]
      allow_origins = ["https://example.com"]
    }
  }

  assert {
    condition     = one(aws_lambda_function_url.submit.cors).allow_origins == toset(["https://example.com"])
    error_message = "submit's Function URL should forward the configured CORS origins."
  }

  assert {
    condition     = length(aws_lambda_function_url.admin.cors) == 0
    error_message = "admin's Function URL has no public browser callers and should not need CORS."
  }
}
