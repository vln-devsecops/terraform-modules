# Public (unauthenticated) Function URL a browser calls directly, with CORS
# handled natively by AWS rather than hand-coded in the handler. See
# tests/aws/lambda/cors_function_url for a provider-backed round-trip that
# exercises this exact shape with real HTTP requests, and
# modules/aws/lambda/README.md for the narrative version of this example.

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

module "lambda" {
  # checkov:skip=CKV_AWS_258:This example deliberately demonstrates a public (NONE-auth) Function URL for a browser-facing endpoint (e.g. an OAuth device-flow proxy an anonymous browser must reach) - not a default any other caller of this module inherits; they set url_authorization_type = "AWS_IAM" for signed access.
  source = "../../../modules/aws/lambda"

  app_name               = var.app_name
  deployment_environment = var.deployment_environment
  function_name          = var.function_name

  source_bucket_arn = var.source_bucket_arn
  source_bucket_id  = var.source_bucket_id
  source_object_key = var.source_object_key

  create_url             = true
  url_authorization_type = "NONE"
  cors = {
    allow_origins = var.cors_allow_origins
    allow_methods = ["POST"]
  }
}

output "function_name" {
  value = module.lambda.function_name
}

output "url" {
  value = module.lambda.url
}
