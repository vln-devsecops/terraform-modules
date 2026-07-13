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
  }
}

provider "aws" {
  region = var.aws_region
}

module "auth" {
  source = "../../../modules/aws/cognito_auth"

  app_name               = var.app_name
  deployment_environment = var.deployment_environment
  route53_zone_id        = var.route53_zone_id
  acm_certificate_arn    = var.acm_certificate_arn
}

output "auth_url" {
  value = module.auth.auth_url
}

output "admin_panel_url" {
  value = module.auth.admin_panel_url
}

output "issuer_url" {
  value = module.auth.issuer_url
}

