terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  effective_app_name   = "${var.app_name}-${var.name_suffix}"
  source_bucket_name   = "deployment-${local.effective_app_name}-${var.deployment_environment}"
  frontend_bucket_name = "frontend-${local.effective_app_name}-${var.deployment_environment}"
  archive_object_key   = "${local.effective_app_name}-origin-response.zip"
}

data "archive_file" "lambda_archive" {
  type        = "zip"
  output_path = "${path.module}/.tmp/origin-response.zip"

  source {
    content  = <<-EOT
      exports.handler = async () => ({
        statusCode: 200,
        body: "ok"
      });
    EOT
    filename = "index.js"
  }
}

resource "aws_s3_bucket" "source" {
  bucket        = local.source_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket                  = aws_s3_bucket.source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "frontend" {
  bucket        = local.frontend_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "lambda_archive" {
  bucket = aws_s3_bucket.source.id
  key    = local.archive_object_key
  source = data.archive_file.lambda_archive.output_path
  etag   = filemd5(data.archive_file.lambda_archive.output_path)
}

resource "aws_iam_user" "backend" {
  name = "backend-user-${var.name_suffix}"
}

module "lambda" {
  source = "../../../../modules/aws/lambda-at-edge"

  app_name               = local.effective_app_name
  deployment_environment = var.deployment_environment
  function_name          = "origin-response"

  source_bucket_arn = aws_s3_bucket.source.arn
  source_bucket_id  = aws_s3_bucket.source.id

  create_secret     = true
  create_url        = true
  backend_user_name = aws_iam_user.backend.name
  s3_required_access = {
    read_frontend = {
      action    = "s3:GetObject"
      resources = ["${aws_s3_bucket.frontend.arn}/*"]
    }
    list_frontend = {
      action    = "s3:ListBucket"
      resources = [aws_s3_bucket.frontend.arn]
    }
  }

  depends_on = [
    aws_s3_object.lambda_archive,
    aws_s3_bucket_public_access_block.source,
    aws_s3_bucket_public_access_block.frontend,
  ]
}

output "function_name" {
  value = module.lambda.function_name
}

output "qualified_arn" {
  value = module.lambda.qualified_arn
}

output "role_name" {
  value = module.lambda.role_name
}

output "secret_name" {
  value = module.lambda.secret_name
}

output "kms_key_arn" {
  value = module.lambda.kms_key_arn
}

output "url" {
  value = module.lambda.url
}

output "edge_replication_policy_arn" {
  value = module.lambda.edge_replication_policy_arn
}
