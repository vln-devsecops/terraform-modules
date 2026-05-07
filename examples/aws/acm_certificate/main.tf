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
  region = "eu-west-1"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "certificate" {
  source = "../../../modules/aws/acm_certificate"

  domain_name         = var.domain_name
  subject_alt_names   = var.subject_alt_names
  route53_zone_id     = var.route53_zone_id
  wait_for_validation = true

  tags = {
    managed_by = "terraform"
  }

  providers = {
    aws = aws.us_east_1
  }
}

output "certificate_arn" {
  value = module.certificate.certificate_arn
}
