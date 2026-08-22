terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "authorizer" {
  source = "../../../modules/aws/http_api_authorizer"

  name        = "example-admin-api"
  require_jwt = true

  jwt_issuer_url     = var.jwt_issuer_url
  jwt_audience       = var.jwt_audience
  jwt_forward_claims = ["tenantId", "permissions"]
}

module "admin_api" {
  source = "../../../modules/aws/http_api"

  name = "example-admin-api"

  lambda_authorizer = {
    authorizer_uri           = module.authorizer.authorizer_uri
    authorizer_function_name = module.authorizer.authorizer_function_name
    identity_sources         = ["$request.header.X-Origin-Verify", "$request.header.Authorization"]
  }

  routes = {
    list_users = {
      route_key            = "GET /users"
      lambda_function_arn  = var.list_users_lambda_arn
      lambda_function_name = var.list_users_lambda_name
      authorization_type   = "CUSTOM"
    }
  }
}

output "api_endpoint" {
  value = module.admin_api.invoke_url
}

output "authorizer_function_name" {
  value = module.authorizer.authorizer_function_name
}

output "origin_verify_secret" {
  value     = module.authorizer.origin_verify_secret
  sensitive = true
}
