variable "deployment_environment" {
  description = "Deployment environment name used for the integration fixture."
  type        = string
  default     = "int"
}

variable "aws_region" {
  description = "AWS region for the integration fixture."
  type        = string
  default     = "us-east-1"
}

variable "base_domain" {
  description = "Parent public domain already delegated to the provided Route53 hosted zone."
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the parent public domain."
  type        = string
}

variable "name_suffix" {
  description = "Unique suffix appended to the integration fixture subdomain."
  type        = string
}
