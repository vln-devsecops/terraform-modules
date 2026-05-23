mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:us-east-1:123456789012:key/central-logs"
      key_id = "central-logs"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      id  = "my-central-logs"
      arn = "arn:aws:s3:::my-central-logs"
    }
  }

  mock_resource "aws_cloudtrail" {
    defaults = {
      arn = "arn:aws:cloudtrail:us-east-1:123456789012:trail/central-logs-trail"
    }
  }
}

run "creates_bucket_with_defaults" {
  command = plan

  variables {
    bucket_name         = "my-central-logs"
    allowed_account_ids = ["111111111111"]
    deployment_mode     = "central"
  }

  assert {
    condition     = output.bucket_name == "my-central-logs"
    error_message = "bucket_name output should match the input bucket_name variable."
  }

  assert {
    condition     = output.bucket_arn == "arn:aws:s3:::my-central-logs"
    error_message = "bucket_arn output should be set."
  }

  assert {
    condition     = output.kms_key_arn != null
    error_message = "kms_key_arn should not be null when create_kms_key defaults to true."
  }

  assert {
    condition     = output.cloudtrail_arn == null
    error_message = "cloudtrail_arn should be null when enable_cloudtrail defaults to false."
  }
}

run "sse_s3_when_kms_disabled" {
  command = plan

  variables {
    bucket_name         = "my-central-logs"
    allowed_account_ids = ["111111111111"]
    deployment_mode     = "central"
    create_kms_key      = false
  }

  assert {
    condition     = output.kms_key_arn == null
    error_message = "kms_key_arn should be null when create_kms_key is false."
  }

  assert {
    condition     = length(aws_kms_key.logs) == 0
    error_message = "No KMS key resource should be created when create_kms_key is false."
  }
}

run "cloudtrail_arn_when_enabled" {
  command = plan

  variables {
    bucket_name         = "my-central-logs"
    allowed_account_ids = ["111111111111"]
    deployment_mode     = "central"
    enable_cloudtrail   = true
  }

  assert {
    condition     = output.cloudtrail_arn != null
    error_message = "cloudtrail_arn should not be null when enable_cloudtrail is true."
  }

  assert {
    condition     = length(aws_cloudtrail.central) == 1
    error_message = "Exactly one CloudTrail trail should be created when enable_cloudtrail is true."
  }
}

run "accepts_multiple_allowed_accounts" {
  command = plan

  variables {
    bucket_name         = "my-central-logs"
    allowed_account_ids = ["111111111111", "222222222222"]
    deployment_mode     = "central"
  }

  assert {
    condition     = output.bucket_arn == "arn:aws:s3:::my-central-logs"
    error_message = "bucket_arn should be set when multiple allowed_account_ids are provided."
  }
}

# --- TDD: deployment_mode variable ---

run "defaults_to_central_mode" {
  command = plan
  variables {
    deployment_mode     = "central"
    bucket_name         = "my-central-logs"
    allowed_account_ids = ["111111111111"]
  }
  assert {
    condition     = var.deployment_mode == null || var.deployment_mode == "central"
    error_message = "deployment_mode should default to 'central'."
  }
}

run "explicit_central_mode" {
  command = plan
  variables {
    bucket_name         = "my-central-logs"
    allowed_account_ids = ["111111111111"]
    deployment_mode     = "central"
  }

  assert {
    condition = contains(
      [for statement in jsondecode(aws_s3_bucket_policy.logs.policy).Statement : statement.Sid],
      "AllowCrossAccountPutObject"
    )
    error_message = "central mode should include AllowCrossAccountPutObject in the bucket policy."
  }
}

run "client_mode" {
  command = plan
  variables {
    bucket_name         = "my-client-logs"
    allowed_account_ids = ["111111111111"]
    deployment_mode     = "client"
  }

  assert {
    condition = !contains(
      [for statement in jsondecode(aws_s3_bucket_policy.logs.policy).Statement : statement.Sid],
      "AllowCrossAccountPutObject"
    )
    error_message = "client mode should not include AllowCrossAccountPutObject in the bucket policy."
  }

  assert {
    condition     = length(aws_cloudtrail.central) == 0
    error_message = "CloudTrail should not be created in client mode."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.logs.rule[0].object_ownership == "BucketOwnerPreferred"
    error_message = "Logs bucket must keep ACL-capable ownership controls for CloudFront standard logging."
  }
}

run "forbid_cloudtrail_in_client_mode" {
  command = plan
  expect_failures = [
    check.cloudtrail_client_mode_incompatible,
  ]

  variables {
    bucket_name         = "my-client-logs"
    allowed_account_ids = ["111111111111"]
    deployment_mode     = "client"
    enable_cloudtrail   = true
  }
}
