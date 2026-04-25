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

module "deployment_bucket" {
  source = "../../../modules/aws/deployment_bucket"

  app_name               = var.app_name
  deployment_environment = var.deployment_environment
  deployment_region      = var.aws_region
}

output "bucket_name" {
  value = module.deployment_bucket.bucket_name
}
