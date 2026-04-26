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
  source = "../../../../modules/aws/lambda"

  app_name               = var.app_name
  deployment_environment = var.deployment_environment
  function_name          = "origin-response"

  source_bucket_arn = var.source_bucket_arn
  source_bucket_id  = var.source_bucket_id

  create_secret     = true
  create_url        = true
  backend_user_name = var.backend_user_name
  assume_role_services = [
    "lambda.amazonaws.com",
    "edgelambda.amazonaws.com",
  ]
  s3_required_access = {
    read_frontend = {
      action    = "s3:GetObject"
      resources = ["${var.frontend_bucket_arn}/*"]
    }
    list_frontend = {
      action    = "s3:ListBucket"
      resources = [var.frontend_bucket_arn]
    }
  }
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
