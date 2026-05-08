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

module "central_logs" {
  source = "../../../modules/aws/central_logs"

  bucket_name         = var.bucket_name
  allowed_account_ids = var.allowed_account_ids
  enable_cloudtrail   = var.enable_cloudtrail

  tags = {
    managed_by = "terraform"
  }
}

output "bucket_name" {
  value = module.central_logs.bucket_name
}

output "bucket_arn" {
  value = module.central_logs.bucket_arn
}

output "kms_key_arn" {
  value = module.central_logs.kms_key_arn
}

output "cloudtrail_arn" {
  value = module.central_logs.cloudtrail_arn
}
