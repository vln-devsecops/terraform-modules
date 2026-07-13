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

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

locals {
  # cognito_auth derives the auth site hostname directly from the zone name
  # plus a prefix (no built-in per-run uniqueness), so the suite bakes the
  # random suffix into the prefix to avoid colliding with concurrent runs.
  domain_prefix    = "auth-${var.name_suffix}"
  auth_site_domain = "${local.domain_prefix}.${var.base_domain}"
}

resource "aws_acm_certificate" "auth" {
  provider          = aws.us_east_1
  domain_name       = local.auth_site_domain
  validation_method = "DNS"
}

resource "aws_route53_record" "auth_validation" {
  for_each = {
    for option in aws_acm_certificate.auth.domain_validation_options :
    option.domain_name => {
      name  = option.resource_record_name
      type  = option.resource_record_type
      value = option.resource_record_value
    }
  }

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.value]
}

resource "aws_acm_certificate_validation" "auth" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.auth.arn
  validation_record_fqdns = [for record in aws_route53_record.auth_validation : record.fqdn]
}

module "cognito_auth" {
  source = "../../../modules/aws/cognito_auth"

  app_name               = "cogauth-${var.name_suffix}"
  deployment_environment = "test"
  route53_zone_id        = var.route53_zone_id
  acm_certificate_arn    = aws_acm_certificate_validation.auth.certificate_arn

  domain_prefix = local.domain_prefix
}

output "user_pool_id" {
  value = module.cognito_auth.user_pool_id
}

output "auth_domain" {
  value = module.cognito_auth.auth_domain
}

output "auth_url" {
  value = module.cognito_auth.auth_url
}

output "admin_panel_url" {
  value = module.cognito_auth.admin_panel_url
}

output "admin_api_invoke_url" {
  value = module.cognito_auth.admin_api_invoke_url
}
