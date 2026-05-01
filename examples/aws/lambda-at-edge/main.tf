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
  region = "us-east-1" # Lambda@Edge functions must be deployed in us-east-1
}

module "origin_response" {
  source = "../../../modules/aws/lambda-at-edge"

  app_name               = var.app_name
  deployment_environment = var.deployment_environment
  function_name          = "origin-response"

  source_bucket_arn = var.source_bucket_arn
  source_bucket_id  = var.source_bucket_id

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
  value = module.origin_response.function_name
}

output "qualified_arn" {
  value = module.origin_response.qualified_arn
}

output "role_name" {
  value = module.origin_response.role_name
}

output "edge_replication_policy_arn" {
  value = module.origin_response.edge_replication_policy_arn
}
