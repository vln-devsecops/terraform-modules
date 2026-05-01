variable "aws_region" {
  description = "AWS region for provider-backed resources."
  type        = string
  default     = "us-east-1"
}

variable "site_name" {
  description = "Fully qualified hostname for the site."
  type        = string
  default     = "dashboard-example.devsecops.vlinder.ca"
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the site hostname."
  type        = string
  default     = "Z1234567890"
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 for the CloudFront alias domain."
  type        = string
  default     = "arn:aws:acm:us-east-1:123456789012:certificate/example"
}
