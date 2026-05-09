# Integration test: verify replication configuration applies with mocked buckets
mock_provider "aws" {
  override_during = apply

  mock_resource "aws_iam_role" {
    defaults = {
      arn  = "arn:aws:iam::123456789012:role/test-replication"
      name = "test-replication"
      id   = "test-replication"
    }
  }

  mock_resource "aws_iam_role_policy" {
    defaults = {}
  }

  mock_resource "aws_s3_bucket_versioning" {
    defaults = {}
  }

  mock_resource "aws_s3_bucket_replication_configuration" {
    defaults = {}
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

run "replication_applies_successfully_with_versioning" {
  command = apply

  variables {
    source_bucket_id       = "test-src-repl"
    source_bucket_arn      = "arn:aws:s3:::test-src-repl"
    destination_bucket_arn = "arn:aws:s3:::test-dst-repl"
    role_name              = "test-replication-role"
    rule_id                = "test-replicate-all"
  }

  # Verify versioning is enabled (required for replication)
  assert {
    condition     = aws_s3_bucket_versioning.source.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be enabled on source bucket for replication."
  }

  # Verify replication configuration exists and targets correct destination
  assert {
    condition     = aws_s3_bucket_replication_configuration.this.bucket == "test-src-repl"
    error_message = "Replication configuration should target the source bucket."
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this.rule[0].destination[0].bucket == "arn:aws:s3:::test-dst-repl"
    error_message = "Replication rule should target the destination bucket ARN."
  }

  # Verify replication role has correct permissions
  assert {
    condition     = aws_iam_role.replication != null && aws_iam_role.replication.assume_role_policy != ""
    error_message = "Replication role should exist with proper assume role policy."
  }

  assert {
    condition     = aws_iam_role_policy.replication != null
    error_message = "Replication role policy with S3 permissions should be attached."
  }
}
