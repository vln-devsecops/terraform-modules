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
  region = var.aws_region
}

locals {
  effective_app_name = "${var.app_name}-${var.name_suffix}"
  source_bucket_name = "deployment-${local.effective_app_name}-${var.deployment_environment}"
}

# No archive is ever uploaded to this bucket, so the module falls back to its
# built-in echo Lambda (see missing_archive_uses_echo_fallback in
# modules/aws/lambda/tests/basic.tftest.hcl) - this fixture only needs a real
# invokable Function URL to prove the cors variable end-to-end, not any
# particular handler behavior.
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

module "lambda" {
  source = "../../../../modules/aws/lambda"

  app_name               = local.effective_app_name
  deployment_environment = var.deployment_environment
  function_name          = "cors-probe"

  source_bucket_arn = aws_s3_bucket.source.arn
  source_bucket_id  = aws_s3_bucket.source.id

  create_url             = true
  url_authorization_type = "NONE"
  cors = {
    allow_origins = [var.allowed_origin]
    allow_methods = ["GET", "POST"]
  }

  depends_on = [
    aws_s3_bucket_public_access_block.source,
  ]
}

output "url" {
  value = module.lambda.url
}

output "function_name" {
  value = module.lambda.function_name
}
