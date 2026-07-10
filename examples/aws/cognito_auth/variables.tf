variable "aws_region" {
  description = "AWS region for provider-backed resources."
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Application name prefix for the single-tenant example."
  type        = string
  default     = "example-app"
}

variable "multi_tenant_app_name" {
  description = "Application name prefix for the multi-tenant example."
  type        = string
  default     = "example-saas"
}

variable "deployment_environment" {
  description = "Deployment environment suffix."
  type        = string
  default     = "dev"
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the derived hostnames."
  type        = string
  default     = "Z1234567890"
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 covering both derived hostnames (a wildcard cert is simplest)."
  type        = string
  default     = "arn:aws:acm:us-east-1:123456789012:certificate/example"
}
