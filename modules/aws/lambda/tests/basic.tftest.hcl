mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:us-east-1:123456789012:key/lambda"
      key_id = "lambda"
    }
  }

  mock_data "aws_s3_object" {
    defaults = {
      checksum_sha256 = "c2FtcGxlLWNoZWNrc3Vt"
      version_id      = "sample-version"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      arn           = "arn:aws:lambda:us-east-1:123456789012:function:sample"
      qualified_arn = "arn:aws:lambda:us-east-1:123456789012:function:sample:1"
    }
  }

  mock_resource "aws_lambda_function_url" {
    defaults = {
      function_url = "https://example.lambda-url.us-east-1.on.aws/"
    }
  }

  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:sample"
    }
  }
}

run "doxchange_defaults_preserve_archive_and_runtime_contract" {
  command = plan

  variables {
    app_name               = "sampleapp"
    deployment_environment = "prod"
    function_name          = "origin-response"
    source_bucket_arn      = "arn:aws:s3:::deployment-sampleapp"
    source_bucket_id       = "deployment-sampleapp"
    kms_key_policy_json    = jsonencode({ Version = "2012-10-17", Statement = [] })
  }

  assert {
    condition     = output.function_name == "sampleapp-origin-response-prod"
    error_message = "Function naming changed unexpectedly."
  }

  assert {
    condition     = aws_lambda_function.this.s3_key == "sampleapp-origin-response.zip"
    error_message = "Default deployment archive naming changed unexpectedly."
  }

  assert {
    condition     = aws_lambda_function.this.runtime == "nodejs22.x" && aws_lambda_function.this.timeout == 3 && aws_lambda_function.this.memory_size == 128
    error_message = "Default Lambda runtime contract changed unexpectedly."
  }

  assert {
    condition = alltrue([
      for tracing in aws_lambda_function.this.tracing_config :
      tracing.mode == "Active"
    ]) && aws_lambda_function.this.kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/lambda" && output.kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/lambda"
    error_message = "Default Lambda encryption or tracing contract changed unexpectedly."
  }

  assert {
    condition     = aws_lambda_function.this.publish == true
    error_message = "Lambda publish should default to true."
  }

  assert {
    condition     = output.role_name == "iam_for_lambda_origin-response_prod_${substr(md5("sampleapp"), 0, 8)}"
    error_message = "Lambda role naming changed unexpectedly."
  }

  assert {
    condition     = output.url == null && output.secret_arn == null && output.secret_name == null
    error_message = "Optional URL or secret outputs should stay null by default."
  }
}

run "explicit_source_key_url_and_policy_attachments_work_together" {
  command = plan

  variables {
    app_name               = "sampleapp"
    deployment_environment = "dev"
    function_name          = "token-service"
    source_bucket_arn      = "arn:aws:s3:::deployment-sampleapp"
    source_bucket_id       = "deployment-sampleapp"
    source_object_key      = "lambdas/token-service/release.zip"
    kms_key_policy_json    = jsonencode({ Version = "2012-10-17", Statement = [] })
    create_url             = true
    url_authorization_type = "AWS_IAM"
    additional_role_policy_arns = [
      "arn:aws:iam::123456789012:policy/custom-lambda-policy",
    ]
    timeout     = 60
    memory_size = 512
    publish     = false
    environment = {
      APP_ENV = "dev"
    }
  }

  assert {
    condition     = aws_lambda_function.this.s3_key == "lambdas/token-service/release.zip"
    error_message = "Explicit source object key was not honored."
  }

  assert {
    condition     = aws_lambda_function.this.timeout == 60 && aws_lambda_function.this.memory_size == 512 && aws_lambda_function.this.publish == false
    error_message = "Explicit Lambda runtime overrides were not honored."
  }

  assert {
    condition     = aws_lambda_function_url.this[0].authorization_type == "AWS_IAM" && output.url == "https://example.lambda-url.us-east-1.on.aws/"
    error_message = "Function URL configuration changed unexpectedly."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.additional[0].policy_arn == "arn:aws:iam::123456789012:policy/custom-lambda-policy"
    error_message = "Additional IAM policy attachments changed unexpectedly."
  }
}

run "doxchange_extensions_cover_secrets_edge_trust_and_extra_s3_access" {
  command = plan

  variables {
    app_name               = "sampleapp"
    deployment_environment = "stage"
    function_name          = "contact-form"
    source_bucket_arn      = "arn:aws:s3:::deployment-sampleapp"
    source_bucket_id       = "deployment-sampleapp"
    kms_key_policy_json    = jsonencode({ Version = "2012-10-17", Statement = [] })
    create_secret          = true
    backend_user_name      = "backend-user"
    assume_role_services = [
      "lambda.amazonaws.com",
      "edgelambda.amazonaws.com",
    ]
    s3_required_access = {
      read_frontend = {
        action    = "s3:GetObject"
        resources = ["arn:aws:s3:::frontend-bucket/*"]
      }
      list_frontend = {
        action    = "s3:ListBucket"
        resources = ["arn:aws:s3:::frontend-bucket"]
      }
    }
  }

  assert {
    condition     = strcontains(local.assume_role_policy, "\"edgelambda.amazonaws.com\"")
    error_message = "Lambda@Edge trust is not present when requested."
  }

  assert {
    condition     = output.secret_name == "sampleapp-contact-form-stage-secrets" && output.secret_arn == "arn:aws:secretsmanager:us-east-1:123456789012:secret:sample"
    error_message = "Secrets Manager outputs changed unexpectedly."
  }

  assert {
    condition     = aws_secretsmanager_secret.this[0].kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/lambda" && aws_kms_key.this[0].enable_key_rotation == true
    error_message = "Secret encryption should use the module-managed KMS key by default."
  }

  assert {
    condition     = aws_iam_user_policy_attachment.backend_user_secrets_access[0].user == "backend-user"
    error_message = "Backend-user secret access attachment changed unexpectedly."
  }

  assert {
    condition     = aws_iam_policy.s3_required_access["read_frontend"].name == "lambda_s3_read_sampleapp_contact-form_stage-read_frontend"
    error_message = "Extra S3 access policy naming changed unexpectedly."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.s3_required_access["list_frontend"].role == output.role_name
    error_message = "Extra S3 access policy attachment changed unexpectedly."
  }
}
