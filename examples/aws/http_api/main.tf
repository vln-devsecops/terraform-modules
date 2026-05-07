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

module "forms_api" {
  source = "../../modules/aws/http_api"

  name = "books-forms"

  cors_configuration = {
    allow_origins = ["https://books.landheer-cieslak.com"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  jwt_authorizers = {
    coppice = {
      issuer_url       = var.coppice_issuer_url
      audience         = ["books.landheer-cieslak.com"]
      identity_sources = ["$request.header.Authorization"]
    }
  }

  routes = {
    contact = {
      route_key            = "POST /contact"
      lambda_function_arn  = var.contact_lambda_arn
      lambda_function_name = var.contact_lambda_name
    }
    newsletter = {
      route_key            = "POST /newsletter"
      lambda_function_arn  = var.newsletter_lambda_arn
      lambda_function_name = var.newsletter_lambda_name
      authorizer_key       = "coppice"
    }
  }

  custom_domain_name            = var.custom_domain_name
  custom_domain_certificate_arn = var.custom_domain_certificate_arn
  route53_zone_id               = var.route53_zone_id

  tags = {
    project    = "books"
    managed_by = "terraform"
  }
}

output "api_endpoint" {
  value = module.forms_api.invoke_url
}
