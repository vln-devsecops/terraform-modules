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

module "github_oidc" {
  source = "../../../modules/aws/github_oidc"

  tags = {
    org     = var.org_name
    managed = "terraform"
  }

  roles = {
    infra_plan = {
      role_name      = "${var.org_name}-infra-plan"
      description    = "Read-only plan role for infra pull requests"
      subject_claims = ["repo:${var.github_org}/${var.infra_repo}:pull_request"]
      policy_arns    = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    }

    infra_apply = {
      role_name      = "${var.org_name}-infra-apply"
      description    = "Write role for infra applies on merge to main"
      subject_claims = ["repo:${var.github_org}/${var.infra_repo}:environment:${var.deploy_environment}"]
      inline_policies = {
        state_access = jsonencode({
          Version = "2012-10-17"
          Statement = [{
            Effect = "Allow"
            Action = [
              "s3:GetObject",
              "s3:PutObject",
              "s3:DeleteObject",
              "s3:ListBucket",
            ]
            Resource = [
              "arn:aws:s3:::${var.state_bucket}",
              "arn:aws:s3:::${var.state_bucket}/*",
            ]
          }]
        })
      }
    }
  }
}

output "oidc_provider_arn" {
  description = "ARN of the created OIDC provider."
  value       = module.github_oidc.oidc_provider_arn
}

output "role_arns" {
  description = "Map of role key to IAM role ARN."
  value       = module.github_oidc.role_arns
}
