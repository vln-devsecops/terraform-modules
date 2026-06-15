terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "aws_kms_key" "buckets" {
  # checkov:skip=CKV2_AWS_64:Example KMS key uses default policy; production callers should provide an explicit policy
  description             = "KMS key for source and destination bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_s3_bucket" "source" {
  # checkov:skip=CKV_AWS_18:Access logging not needed for example bucket
  # checkov:skip=CKV2_AWS_61:Example bucket with force_destroy for test cleanup
  # checkov:skip=CKV2_AWS_62:Event notifications not needed for example bucket
  bucket        = var.source_bucket_name
  force_destroy = true
  tags = {
    Name = "source-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket                  = aws_s3_bucket.source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.buckets.arn
    }
  }
}

resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "destination" {
  # checkov:skip=CKV_AWS_18:Access logging not needed for example bucket
  # checkov:skip=CKV2_AWS_61:Example bucket with force_destroy for test cleanup
  # checkov:skip=CKV2_AWS_62:Event notifications not needed for example bucket
  bucket        = var.destination_bucket_name
  force_destroy = true
  tags = {
    Name = "destination-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "destination" {
  bucket                  = aws_s3_bucket.destination.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "destination" {
  bucket = aws_s3_bucket.destination.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.buckets.arn
    }
  }
}

resource "aws_s3_bucket_versioning" "destination" {
  bucket = aws_s3_bucket.destination.id

  versioning_configuration {
    status = "Enabled"
  }
}

module "s3_replication" {
  source = "../../../modules/aws/s3_replication"

  source_bucket_id       = aws_s3_bucket.source.id
  source_bucket_arn      = aws_s3_bucket.source.arn
  destination_bucket_arn = aws_s3_bucket.destination.arn
  role_name              = "example-s3-replication"
  rule_id                = "replicate-example-objects"
  tags = {
    Environment = "example"
  }

  depends_on = [
    aws_s3_bucket_versioning.source,
    aws_s3_bucket_versioning.destination,
  ]
}

