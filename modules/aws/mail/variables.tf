variable "deployment_environment" {
  description = "The deployment environment name such as dev, staging, or prod."
  type        = string
}

variable "deployment_region" {
  description = "Primary AWS region associated with this mail configuration."
  type        = string
}

variable "domain_name" {
  description = "Fully qualified domain name for the SES identity."
  type        = string
}

variable "domain_prefix" {
  description = "Subdomain label used for Route53 records within the hosted zone."
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID where the mail DNS records should be created."
  type        = string
}

variable "ses_inbound_region" {
  description = "Optional AWS region for the inbound SMTP MX target. Defaults to deployment_region."
  type        = string
  default     = null
}

variable "ses_feedback_region" {
  description = "Optional AWS region for the MAIL FROM feedback SMTP target. Defaults to deployment_region."
  type        = string
  default     = null
}

variable "tracking_redirect_domain" {
  description = "Optional custom redirect domain for the SES configuration set."
  type        = string
  default     = null
}

variable "dmarc_policy" {
  description = "Optional DMARC policy value such as reject, quarantine, or none. Defaults to reject."
  type        = string
  default     = null
}

variable "dmarc_report_uri" {
  description = "Optional DMARC report URI such as mailto:dmarc-reports@example.com. Defaults to a domain-local mailbox."
  type        = string
  default     = null
}
