mock_provider "aws" {
  override_during = plan
}

run "bucket_name_and_outputs_match_contract" {
  command = plan

  variables {
    app_name               = "sampleapp"
    deployment_environment = "dev"
    deployment_region      = "us-east-1"
  }

  assert {
    condition     = output.bucket_name == "sampleapp-deployment-bucket-dev-us-east-1"
    error_message = "Bucket naming contract changed unexpectedly."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls && aws_s3_bucket_public_access_block.this.block_public_policy && aws_s3_bucket_public_access_block.this.ignore_public_acls && aws_s3_bucket_public_access_block.this.restrict_public_buckets
    error_message = "Public access block settings changed unexpectedly."
  }
}
