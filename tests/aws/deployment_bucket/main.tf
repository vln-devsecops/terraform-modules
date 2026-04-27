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
}

module "deployment_bucket" {
  source = "../../../modules/aws/deployment_bucket"

  app_name               = local.effective_app_name
  deployment_environment = var.deployment_environment
  deployment_region      = var.aws_region
}

output "bucket_name" {
  value = module.deployment_bucket.bucket_name
}

output "kms_key_arn" {
  value = module.deployment_bucket.kms_key_arn
}
