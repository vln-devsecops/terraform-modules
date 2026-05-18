locals {
  kms_key_arn         = coalesce(var.kms_key_arn, aws_kms_key.this[0].arn)
  kms_key_policy_json = var.kms_key_policy_json != null ? var.kms_key_policy_json : data.aws_iam_policy_document.kms.json
  common_tags = {
    app         = var.app_name
    environment = var.deployment_environment
    rg          = "security"
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kms" {
  statement {
    sid    = "EnableRootPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }
}

resource "aws_s3_bucket" "this" {
  bucket = "${var.app_name}-deployment-bucket-${var.deployment_environment}-${var.deployment_region}"
}

resource "aws_kms_key" "this" {
  count = var.kms_key_arn == null ? 1 : 0

  description             = "CMK for deployment artifacts in ${var.app_name}-${var.deployment_environment}-${var.deployment_region}"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = local.kms_key_policy_json
  tags                    = merge(local.common_tags, var.tags)
}

resource "aws_kms_alias" "this" {
  count = var.kms_key_arn == null ? 1 : 0

  name          = "alias/${var.app_name}-${var.deployment_environment}-${var.deployment_region}-deployment-bucket"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = local.kms_key_arn
      sse_algorithm     = "aws:kms"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
