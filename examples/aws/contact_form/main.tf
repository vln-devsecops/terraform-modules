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

module "contact_form" {
  source = "../../../modules/aws/contact_form"

  app_name                     = var.app_name
  deployment_environment       = var.deployment_environment
  admin_allowed_principal_arns = var.admin_allowed_principal_arns

  submit_cors = {
    allow_methods = ["POST"]
    allow_origins = var.submit_allowed_origins
  }
}

output "submit_function_url" {
  value = module.contact_form.submit_function_url
}

output "admin_function_url" {
  value = module.contact_form.admin_function_url
}

output "recaptcha_secret_arn" {
  value = module.contact_form.recaptcha_secret_arn
}
