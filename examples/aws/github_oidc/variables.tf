variable "aws_region" {
  description = "AWS region for the provider."
  type        = string
  default     = "us-east-1"
}

variable "org_name" {
  description = "Short organisation name used as a prefix in IAM role names."
  type        = string
}

variable "github_org" {
  description = "GitHub organisation or user that owns the repos."
  type        = string
}

variable "infra_repo" {
  description = "Name of the infrastructure repository."
  type        = string
  default     = "infra"
}

variable "deploy_environment" {
  description = "GitHub Actions environment name used for the apply role trust condition."
  type        = string
  default     = "production"
}

variable "state_bucket" {
  description = "S3 bucket name used for Terraform state."
  type        = string
}
