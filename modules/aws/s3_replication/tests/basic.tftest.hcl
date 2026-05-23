mock_provider "aws" {
  override_during = plan

  mock_resource "aws_iam_role" {
    defaults = {
      arn  = "arn:aws:iam::123456789012:role/cloudfront-log-replication"
      name = "cloudfront-log-replication"
      id   = "cloudfront-log-replication"
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

run "creates_replication_role_and_configuration" {
  command = plan

  variables {
    source_bucket_id       = "my-cloudfront-logs"
    source_bucket_arn      = "arn:aws:s3:::my-cloudfront-logs"
    destination_bucket_arn = "arn:aws:s3:::central-logs"
    role_name              = "cloudfront-log-replication"
  }

  assert {
    condition     = output.replication_role_arn != ""
    error_message = "replication_role_arn output should be set."
  }

  assert {
    condition     = output.replication_role_name == "cloudfront-log-replication"
    error_message = "replication_role_name output should match the role_name variable."
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this.bucket == "my-cloudfront-logs"
    error_message = "Replication configuration should target the source bucket."
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this.rule[0].id == "replicate-to-central-logs"
    error_message = "Replication rule ID should default to replicate-to-central-logs."
  }
}

run "custom_rule_id_is_applied" {
  command = plan

  variables {
    source_bucket_id       = "my-cloudfront-logs"
    source_bucket_arn      = "arn:aws:s3:::my-cloudfront-logs"
    destination_bucket_arn = "arn:aws:s3:::central-logs"
    role_name              = "cloudfront-log-replication"
    rule_id                = "replicate-books-cloudfront-to-devsecops"
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this.rule[0].id == "replicate-books-cloudfront-to-devsecops"
    error_message = "Replication rule ID should match the custom rule_id variable."
  }
}

run "custom_storage_class_is_applied" {
  command = plan

  variables {
    source_bucket_id          = "my-cloudfront-logs"
    source_bucket_arn         = "arn:aws:s3:::my-cloudfront-logs"
    destination_bucket_arn    = "arn:aws:s3:::central-logs"
    role_name                 = "cloudfront-log-replication"
    destination_storage_class = "GLACIER_IR"
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this.rule[0].destination[0].storage_class == "GLACIER_IR"
    error_message = "Destination storage class should match destination_storage_class variable."
  }
}

run "versioning_enabled_on_source" {
  command = plan

  variables {
    source_bucket_id       = "my-cloudfront-logs"
    source_bucket_arn      = "arn:aws:s3:::my-cloudfront-logs"
    destination_bucket_arn = "arn:aws:s3:::central-logs"
    role_name              = "cloudfront-log-replication"
  }

  assert {
    condition     = aws_s3_bucket_versioning.source[0].versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be Enabled on the source bucket."
  }
}

run "can_skip_source_versioning_management" {
  command = plan

  variables {
    source_bucket_id                 = "my-cloudfront-logs"
    source_bucket_arn                = "arn:aws:s3:::my-cloudfront-logs"
    destination_bucket_arn           = "arn:aws:s3:::central-logs"
    role_name                        = "cloudfront-log-replication"
    manage_source_bucket_versioning  = false
  }

  assert {
    condition     = length(aws_s3_bucket_versioning.source) == 0
    error_message = "Source bucket versioning resource should be skipped when versioning is managed elsewhere."
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this.bucket == "my-cloudfront-logs"
    error_message = "Replication configuration should still target the source bucket when versioning management is disabled."
  }
}
