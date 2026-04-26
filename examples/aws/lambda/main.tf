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
  source = "../../../modules/aws/lambda"

  app_name               = var.app_name
  deployment_environment = var.deployment_environment
  function_name          = var.function_name

  source_bucket_arn = var.source_bucket_arn
  source_bucket_id  = var.source_bucket_id
  source_object_key = var.source_object_key

  create_url             = true
  url_authorization_type = "AWS_IAM"
  timeout                = 30
  memory_size            = 256

  environment = {
    APP_ENV = var.deployment_environment
  }
}

output "function_name" {
  value = module.lambda.function_name
}

output "role_name" {
  value = module.lambda.role_name
}
