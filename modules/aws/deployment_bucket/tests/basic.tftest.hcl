mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:us-east-1:123456789012:key/deployment-bucket"
      key_id = "deployment-bucket"
    }
  }
}

run "bucket_name_and_outputs_match_contract" {
  command = plan

  variables {
    app_name               = "sampleapp"
    deployment_environment = "dev"
    deployment_region      = "us-east-1"
    kms_key_policy_json    = jsonencode({ Version = "2012-10-17", Statement = [] })
  }

  assert {
    condition     = output.bucket_name == "sampleapp-deployment-bucket-dev-us-east-1"
    error_message = "Bucket naming contract changed unexpectedly."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls && aws_s3_bucket_public_access_block.this.block_public_policy && aws_s3_bucket_public_access_block.this.ignore_public_acls && aws_s3_bucket_public_access_block.this.restrict_public_buckets
    error_message = "Public access block settings changed unexpectedly."
  }

  assert {
    condition = length(aws_s3_bucket_server_side_encryption_configuration.this.rule) == 1 && alltrue([
      for rule in aws_s3_bucket_server_side_encryption_configuration.this.rule :
      rule.bucket_key_enabled && alltrue([
        for enc in rule.apply_server_side_encryption_by_default :
        enc.sse_algorithm == "aws:kms"
      ])
    ])
    error_message = "Bucket encryption defaults changed unexpectedly."
  }

  assert {
    condition     = aws_kms_key.this[0].enable_key_rotation == true && output.kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/deployment-bucket"
    error_message = "Module-managed KMS key behavior changed unexpectedly."
  }
}
