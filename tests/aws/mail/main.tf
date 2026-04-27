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
  domain_label = "mail-${var.name_suffix}"
  domain_name  = "${local.domain_label}.${var.base_domain}"
}

module "mail" {
  source = "../../../modules/aws/mail"

  deployment_environment = var.deployment_environment
  deployment_region      = var.aws_region
  domain_name            = local.domain_name
  domain_prefix          = local.domain_label
  route53_zone_id        = var.route53_zone_id
}

output "configuration_set_name" {
  value = module.mail.configuration_set_name
}

output "identity_arn" {
  value = module.mail.identity_arn
}

output "mail_from_domain" {
  value = module.mail.mail_from_domain
}

output "domain_name" {
  value = local.domain_name
}
