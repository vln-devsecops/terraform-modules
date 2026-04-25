variable "deployment_environment" {
  description = "Deployment environment name such as dev, staging, or prod."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for the example deployment."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Fully qualified domain name for the SES identity."
  type        = string
  default     = "auth.example.com"
}

variable "domain_prefix" {
  description = "Subdomain label used for Route53 records."
  type        = string
  default     = "auth"
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the example DNS records."
  type        = string
  default     = "Z1234567890"
}
