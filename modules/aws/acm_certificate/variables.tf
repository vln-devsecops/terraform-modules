variable "domain_name" {
  description = "Primary domain name for the certificate."
  type        = string
}

variable "subject_alt_names" {
  description = "Subject alternative names to include in the certificate."
  type        = list(string)
  default     = []
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID used for DNS validation records."
  type        = string
}

variable "validation_method" {
  description = "Certificate validation method."
  type        = string
  default     = "DNS"
  validation {
    condition     = var.validation_method == "DNS"
    error_message = "Only DNS validation is supported by this module."
  }
}

variable "wait_for_validation" {
  description = "Whether to wait for certificate validation to complete before returning."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to the certificate."
  type        = map(string)
  default     = {}
}
