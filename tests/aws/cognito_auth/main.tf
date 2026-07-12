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
  # cognito_auth derives its hosted-UI and admin-panel hostnames directly
  # from the zone name plus a prefix (no built-in per-run uniqueness), so the
  # suite bakes the random suffix into both prefixes to avoid colliding with
  # concurrent runs or real usage of the shared delegated test domain.
  domain_prefix             = "auth-${var.name_suffix}"
  admin_panel_domain_prefix = "admin-${var.name_suffix}"
  # cognito_auth joins domain_prefix and the zone's base domain with a dot
  # (see modules/aws/cognito_auth/main.tf's hosted_ui_domain local) -- match
  # that exactly here so the cert's SANs cover what the module actually
  # requests.
  hosted_ui_hostname   = "${local.domain_prefix}.${var.base_domain}"
  admin_panel_hostname = "${local.admin_panel_domain_prefix}.${var.base_domain}"
}

resource "aws_acm_certificate" "auth" {
  provider                  = aws.us_east_1
  domain_name               = local.hosted_ui_hostname
  subject_alternative_names = [local.admin_panel_hostname]
  validation_method         = "DNS"
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

  domain_prefix             = local.domain_prefix
  admin_panel_domain_prefix = local.admin_panel_domain_prefix
}

output "user_pool_id" {
  value = module.cognito_auth.user_pool_id
}

output "hosted_ui_domain" {
  value = module.cognito_auth.hosted_ui_domain
}

output "hosted_ui_url" {
  value = module.cognito_auth.hosted_ui_url
}

output "admin_panel_url" {
  value = module.cognito_auth.admin_panel_url
}

output "admin_api_invoke_url" {
  value = module.cognito_auth.admin_api_invoke_url
}
