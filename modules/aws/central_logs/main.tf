data "aws_caller_identity" "current" {}

resource "aws_kms_key" "logs" {
  # checkov:skip=CKV2_AWS_64:KMS key uses default policy rather than an explicit delegation statement; callers can override via var.create_kms_key
  count = var.create_kms_key ? 1 : 0

  description             = "KMS key for central logs bucket ${var.bucket_name}"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_key_deletion_window_days

  tags = var.tags
}

resource "aws_kms_alias" "logs" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${var.bucket_name}"
  target_key_id = aws_kms_key.logs[0].key_id
}

# trivy:ignore:AVD-AWS-0089
resource "aws_s3_bucket" "logs" {
  # checkov:skip=CKV_AWS_18:Access logging for a log bucket would create a circular dependency
  # checkov:skip=CKV_AWS_144:Cross-region replication caller-configurable, not wired at module level
  # checkov:skip=CKV2_AWS_62:Event notifications caller-configurable, not wired at module level
  bucket        = var.bucket_name
  force_destroy = false

  tags = var.tags
}

# CloudFront standard logging requires bucket ACL support.
resource "aws_s3_bucket_ownership_controls" "logs" {
  # checkov:skip=CKV2_AWS_65:CloudFront standard logging and cross-account S3 PutObject delivery require ACL support
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.create_kms_key ? "aws:kms" : "AES256"
      kms_master_key_id = var.create_kms_key ? aws_kms_key.logs[0].arn : null
    }
    bucket_key_enabled = var.create_kms_key ? true : false
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "retain-and-archive"
    status = "Enabled"

    transition {
      days          = var.standard_retention_days
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = var.standard_retention_days + var.glacier_retention_years * 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "DenyInsecureTransport"
          Effect = "Deny"
          Principal = {
            AWS = "*"
          }
          Action   = "s3:*"
          Resource = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
          Condition = {
            Bool = {
              "aws:SecureTransport" = "false"
            }
          }
        }
      ],
      var.deployment_mode == "central" ? [
        {
          Sid    = "AllowCrossAccountPutObject"
          Effect = "Allow"
          Principal = {
            AWS = [for account_id in var.allowed_account_ids : "arn:aws:iam::${account_id}:root"]
          }
          Action   = "s3:PutObject"
          Resource = "${aws_s3_bucket.logs.arn}/*"
          Condition = {
            StringEquals = {
              "s3:x-amz-acl" = "bucket-owner-full-control"
            }
          }
        }
      ] : [],
      var.deployment_mode == "central" && var.enable_cloudtrail ? [
        {
          Sid    = "AllowCloudTrailDelivery"
          Effect = "Allow"
          Principal = {
            Service = "cloudtrail.amazonaws.com"
          }
          Action = ["s3:GetBucketAcl", "s3:PutObject"]
          Resource = [
            aws_s3_bucket.logs.arn,
            "${aws_s3_bucket.logs.arn}/cloudtrail/AWSLogs/*",
          ]
          Condition = {
            StringEquals = {
              "aws:SourceArn" = "arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/${var.cloudtrail_name}"
            }
          }
        }
      ] : []
    )
  })
}

resource "aws_cloudtrail" "central" {
  # checkov:skip=CKV2_AWS_10:CloudWatch Logs integration caller-configurable, not wired at module level
  count = var.deployment_mode == "central" && var.enable_cloudtrail ? 1 : 0

  name                          = var.cloudtrail_name
  s3_bucket_name                = aws_s3_bucket.logs.id
  s3_key_prefix                 = "cloudtrail"
  enable_log_file_validation    = true
  is_multi_region_trail         = true
  include_global_service_events = true
  kms_key_id                    = var.create_kms_key ? aws_kms_key.logs[0].arn : null

  depends_on = [aws_s3_bucket_policy.logs]

  tags = var.tags
}
