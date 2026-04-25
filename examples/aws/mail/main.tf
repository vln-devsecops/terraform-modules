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

module "mail" {
  source = "../../../modules/aws/mail"

  deployment_environment = var.deployment_environment
  deployment_region      = var.aws_region
  domain_name            = var.domain_name
  domain_prefix          = var.domain_prefix
  route53_zone_id        = var.route53_zone_id
}

output "configuration_set_name" {
  value = module.mail.configuration_set_name
}
