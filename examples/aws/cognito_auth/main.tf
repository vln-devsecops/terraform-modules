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

# Two illustrative scenarios below. In practice these would target different
# Route53 zones (each deployment derives auth-<zone> and admin-<zone>
# hostnames, which would collide if both really pointed at the same zone).

# Scenario 1: single-tenant (the default) -- minimal input, everything else defaulted.
module "auth" {
  source = "../../../modules/aws/cognito_auth"

  app_name               = var.app_name
  deployment_environment = var.deployment_environment
  route53_zone_id        = var.route53_zone_id
  acm_certificate_arn    = var.acm_certificate_arn
}

# Scenario 2: multi-tenant with a custom role catalog, including a
# cross-tenant super-admin role (tenant_scope = "global").
module "auth_multi_tenant" {
  source = "../../../modules/aws/cognito_auth"

  app_name               = var.multi_tenant_app_name
  deployment_environment = var.deployment_environment
  route53_zone_id        = var.route53_zone_id
  acm_certificate_arn    = var.acm_certificate_arn

  tenancy_mode = "multi"
  tenants = {
    acme-corp = {
      name         = "Acme Corp"
      email_domain = "acme.example.com"
    }
    globex = {
      name         = "Globex"
      email_domain = "globex.example.com"
    }
  }

  roles = {
    member = {
      privileges   = []
      tenant_scope = "tenant"
    }
    tenant-admin = {
      privileges   = ["admin:users:read:own", "admin:users:write:own", "admin:roles:read"]
      tenant_scope = "tenant"
    }
    super-admin = {
      privileges   = ["admin:users:read:*", "admin:users:write:*", "admin:roles:read"]
      tenant_scope = "global"
    }
  }
}

output "hosted_ui_url" {
  value = module.auth.hosted_ui_url
}

output "admin_panel_url" {
  value = module.auth.admin_panel_url
}

output "multi_tenant_issuer_url" {
  value = module.auth_multi_tenant.issuer_url
}
