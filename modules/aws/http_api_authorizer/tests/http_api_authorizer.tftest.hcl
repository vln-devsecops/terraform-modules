mock_provider "aws" {
  override_during = plan

  mock_resource "aws_lambda_function" {
    defaults = {
      arn        = "arn:aws:lambda:eu-west-1:123456789012:function:placeholder"
      invoke_arn = "arn:aws:apigateway:eu-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-1:123456789012:function:placeholder/invocations"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
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

run "origin_check_only_by_default" {
  command = plan

  variables {
    name = "myapp-prod-auth-api"
  }

  assert {
    condition     = aws_lambda_function.this.function_name == "myapp-prod-auth-api-authorizer"
    error_message = "Lambda function name must be name-authorizer."
  }

  assert {
    condition     = aws_lambda_function.this.handler == "handler.handler"
    error_message = "Handler must be handler.handler to match the package's single bundled entry point."
  }

  assert {
    condition     = contains(keys(one(aws_lambda_function.this.environment).variables), "ORIGIN_VERIFY_SECRET")
    error_message = "ORIGIN_VERIFY_SECRET must always be set."
  }

  assert {
    condition     = !contains(keys(one(aws_lambda_function.this.environment).variables), "REQUIRE_JWT")
    error_message = "REQUIRE_JWT must not be set when require_jwt is false."
  }
}

run "require_jwt_sets_jwt_env_vars" {
  command = plan

  variables {
    name               = "myapp-prod-admin-api"
    require_jwt        = true
    jwt_issuer_url     = "https://cognito-idp.eu-west-1.amazonaws.com/eu-west-1_example"
    jwt_audience       = "client-id-123"
    jwt_forward_claims = ["tenantId", "permissions"]
  }

  assert {
    condition     = one(aws_lambda_function.this.environment).variables["REQUIRE_JWT"] == "true"
    error_message = "REQUIRE_JWT must be \"true\" when require_jwt is true."
  }

  assert {
    condition     = one(aws_lambda_function.this.environment).variables["JWT_ISSUER_URL"] == "https://cognito-idp.eu-west-1.amazonaws.com/eu-west-1_example"
    error_message = "JWT_ISSUER_URL must match jwt_issuer_url."
  }

  assert {
    condition     = one(aws_lambda_function.this.environment).variables["JWT_AUDIENCE"] == "client-id-123"
    error_message = "JWT_AUDIENCE must match jwt_audience."
  }

  assert {
    condition     = one(aws_lambda_function.this.environment).variables["JWT_FORWARD_CLAIMS"] == "tenantId,permissions"
    error_message = "JWT_FORWARD_CLAIMS must be a comma-joined list of jwt_forward_claims."
  }

  assert {
    condition     = output.jwt_audience == "client-id-123"
    error_message = "jwt_audience output must match jwt_audience, for callers' own contract tests to assert against."
  }
}

run "jwt_resource_is_set_independently_of_jwt_audience" {
  command = plan

  variables {
    name               = "myapp-prod-admin-api"
    require_jwt        = true
    jwt_issuer_url     = "https://cognito-idp.eu-west-1.amazonaws.com/eu-west-1_example"
    jwt_resource       = "admin-api"
    jwt_forward_claims = ["tenantId", "permissions"]
  }

  assert {
    condition     = one(aws_lambda_function.this.environment).variables["JWT_RESOURCE"] == "admin-api"
    error_message = "JWT_RESOURCE must match jwt_resource."
  }

  assert {
    condition     = !contains(keys(one(aws_lambda_function.this.environment).variables), "JWT_AUDIENCE")
    error_message = "JWT_AUDIENCE should be entirely absent when jwt_audience is not set, not an empty/null value."
  }

  assert {
    condition     = output.jwt_resource == "admin-api"
    error_message = "jwt_resource output must match jwt_resource, for callers' own contract tests to assert against."
  }
}

run "outputs_expose_authorizer_wiring" {
  command = plan

  variables {
    name = "myapp-prod-auth-api"
  }

  override_resource {
    target          = random_password.origin_verify_secret
    override_during = plan
    values = {
      result = "mock-generated-secret" # checkov:skip=CKV_SECRET_6:Test fixture placeholder, not a real secret
    }
  }

  assert {
    condition     = output.authorizer_uri == aws_lambda_function.this.invoke_arn
    error_message = "authorizer_uri output must be the Lambda invoke ARN."
  }

  assert {
    condition     = output.authorizer_function_name == aws_lambda_function.this.function_name
    error_message = "authorizer_function_name output must be the Lambda function name."
  }

  assert {
    condition     = output.origin_verify_secret == "mock-generated-secret" # checkov:skip=CKV_SECRET_6:Test fixture placeholder, not a real secret
    error_message = "origin_verify_secret output must be the generated secret."
  }
}

run "no_kms_policy_without_a_kms_key" {
  command = plan

  # create_kms_policy left at its default (null): with kms_key_arn also
  # unset, the inference path (see variables.tf) falls back to "false".
  variables {
    name = "myapp-prod-auth-api"
  }

  assert {
    condition     = length(aws_iam_policy.kms) == 0
    error_message = "No KMS policy should be created when kms_key_arn is unset."
  }

  assert {
    condition     = aws_lambda_function.this.kms_key_arn == null
    error_message = "Lambda should use default encryption when kms_key_arn is unset."
  }
}

run "kms_policy_created_by_inference_when_create_kms_policy_is_left_unset" {
  command = plan

  # This is the inference path itself, not just its "both unset" edge case:
  # create_kms_policy is left at its default (null) and kms_key_arn is a
  # plan-time-known literal, so count falls back to `kms_key_arn != null`
  # -- the pre-this-PR behavior, preserved for any caller who doesn't know
  # about create_kms_policy and whose kms_key_arn is statically known (the
  # common case for anyone other than vlinder_auth). A test that never sets
  # create_kms_policy at all but still expects the resources to be gated
  # correctly is the one thing that actually distinguishes a correct
  # inference from a broken one (e.g. a gate that's hardcoded to false).
  variables {
    name        = "myapp-prod-auth-api"
    kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = length(aws_iam_policy.kms) == 1
    error_message = "A known, non-null kms_key_arn should imply the KMS policy is created even when create_kms_policy is left unset."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.kms) == 1
    error_message = "A known, non-null kms_key_arn should imply the KMS policy attachment is created even when create_kms_policy is left unset."
  }

  assert {
    condition     = aws_lambda_function.this.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    error_message = "Lambda should be encrypted with the supplied CMK."
  }
}

run "no_kms_policy_when_create_kms_policy_explicitly_false" {
  command = plan

  # An explicit false always wins over kms_key_arn's nullness, even when
  # kms_key_arn is set -- the caller-supplied boolean, when given, takes
  # priority over inference.
  variables {
    name              = "myapp-prod-auth-api"
    kms_key_arn       = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    create_kms_policy = false
  }

  assert {
    condition     = length(aws_iam_policy.kms) == 0
    error_message = "No KMS policy should be created when create_kms_policy is explicitly false, regardless of kms_key_arn."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.kms) == 0
    error_message = "No KMS policy attachment should be created when create_kms_policy is explicitly false, regardless of kms_key_arn."
  }

  assert {
    condition     = aws_lambda_function.this.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    error_message = "Lambda should still be encrypted with the supplied CMK even when create_kms_policy is false."
  }
}

run "kms_policy_grants_decrypt_on_the_supplied_key" {
  command = plan

  # An explicit true is what a caller in vlinder_auth's position needs: its
  # kms_key_arn is a same-apply-computed value (unknown at plan time in
  # real usage), so the inference path can't be relied on there -- only a
  # mocked/literal ARN is used here because terraform test's mocked
  # providers make every value "known" regardless.
  variables {
    name              = "myapp-prod-auth-api"
    kms_key_arn       = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    create_kms_policy = true
  }

  assert {
    condition     = length(aws_iam_policy.kms) == 1
    error_message = "Expected exactly one KMS policy when create_kms_policy is true."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.kms) == 1
    error_message = "Expected exactly one KMS policy attachment when create_kms_policy is true."
  }

  assert {
    condition     = strcontains(aws_iam_policy.kms[0].policy, "kms:Decrypt")
    error_message = "The KMS policy must grant Decrypt on the supplied key."
  }

  assert {
    condition     = strcontains(aws_iam_policy.kms[0].policy, var.kms_key_arn)
    error_message = "The KMS policy's Resource must be the supplied kms_key_arn."
  }

  assert {
    condition     = aws_lambda_function.this.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    error_message = "Lambda should be encrypted with the supplied CMK."
  }
}

run "create_kms_policy_true_with_null_kms_key_arn_fails_validation" {
  command = plan

  # The real, distinct misconfiguration this validation guards against:
  # nothing to grant kms:Decrypt on if kms_key_arn is null.
  variables {
    name              = "myapp-prod-auth-api"
    kms_key_arn       = null
    create_kms_policy = true
  }

  expect_failures = [
    var.create_kms_policy,
  ]
}
