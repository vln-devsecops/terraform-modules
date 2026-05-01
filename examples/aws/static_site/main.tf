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

module "static_site" {
  source = "../../../modules/aws/static_site"

  site_name           = var.site_name
  route53_zone_id     = var.route53_zone_id
  acm_certificate_arn = var.acm_certificate_arn
}

output "site_url" {
  value = module.static_site.site_url
}

output "bucket_name" {
  value = module.static_site.bucket_name
}
