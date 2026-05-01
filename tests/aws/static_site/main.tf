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

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

locals {
  site_label = "site-${var.name_suffix}"
  site_name  = "${local.site_label}.${var.base_domain}"
}

resource "aws_acm_certificate" "site" {
  provider          = aws.us_east_1
  domain_name       = local.site_name
  validation_method = "DNS"
}

resource "aws_route53_record" "site_validation" {
  for_each = {
    for option in aws_acm_certificate.site.domain_validation_options :
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

resource "aws_acm_certificate_validation" "site" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for record in aws_route53_record.site_validation : record.fqdn]
}

module "static_site" {
  source = "../../../modules/aws/static_site"

  site_name           = local.site_name
  route53_zone_id     = var.route53_zone_id
  acm_certificate_arn = aws_acm_certificate_validation.site.certificate_arn
}

output "bucket_name" {
  value = module.static_site.bucket_name
}

output "distribution_id" {
  value = module.static_site.cloudfront_distribution_id
}

output "site_url" {
  value = module.static_site.site_url
}

output "cloudfront_domain_name" {
  value = module.static_site.cloudfront_domain_name
}

output "site_name" {
  value = module.static_site.site_name
}
