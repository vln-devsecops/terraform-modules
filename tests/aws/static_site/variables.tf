variable "aws_region" {
  description = "AWS region for the Route53-backed test resources."
  type        = string
  default     = "us-east-1"
}

variable "name_suffix" {
  description = "Random suffix used to keep test resources unique."
  type        = string
}

variable "base_domain" {
  description = "Delegated public base domain used for provider-backed tests."
  type        = string
}

variable "route53_zone_id" {
  description = "Hosted zone ID for the delegated public base domain."
  type        = string
}
