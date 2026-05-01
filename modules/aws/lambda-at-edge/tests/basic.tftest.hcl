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

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock-policy"
    }
  }
}

run "creates_lambda_and_replication_resources" {
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
    condition     = aws_iam_policy.edge_replication.name == "sampleapp_origin-response_prod_lambda_edge_replication_policy"
    error_message = "Edge replication policy name does not follow module naming convention."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.edge_replication.role == module.lambda.role_name
    error_message = "Edge replication attachment should reference the Lambda execution role."
  }
}

run "function_naming_convention_preserved" {
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
    error_message = "Function naming convention changed unexpectedly."
  }

  assert {
    condition     = module.lambda.arn == "arn:aws:lambda:us-east-1:123456789012:function:sample"
    error_message = "Lambda ARN output changed unexpectedly."
  }
}

run "outputs_are_fully_proxied" {
  command = plan

  variables {
    app_name               = "sampleapp"
    deployment_environment = "dev"
    function_name          = "origin-response"
    source_bucket_arn      = "arn:aws:s3:::deployment-sampleapp"
    source_bucket_id       = "deployment-sampleapp"
    kms_key_policy_json    = jsonencode({ Version = "2012-10-17", Statement = [] })
  }

  assert {
    condition     = output.qualified_arn == "arn:aws:lambda:us-east-1:123456789012:function:sample:1"
    error_message = "qualified_arn output must be proxied from inner lambda module."
  }

  assert {
    condition     = output.edge_replication_policy_arn == "arn:aws:iam::123456789012:policy/mock-policy"
    error_message = "edge_replication_policy_arn output must be set."
  }

  assert {
    condition     = output.url == null && output.secret_arn == null && output.secret_name == null
    error_message = "Optional outputs should be null when not enabled."
  }
}
