variable "site_name" {
  description = "Fully qualified hostname for the static site."
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID that serves the site hostname."
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 for the CloudFront alias domain."
  type        = string
}

variable "default_root_object" {
  description = "Default root object served by CloudFront."
  type        = string
  default     = "index.html"
}

variable "cloudfront_price_class" {
  description = "CloudFront price class for the site distribution."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition = contains([
      "PriceClass_All",
      "PriceClass_200",
      "PriceClass_100",
    ], var.cloudfront_price_class)
    error_message = "cloudfront_price_class must be PriceClass_All, PriceClass_200, or PriceClass_100."
  }
}

variable "http_version" {
  description = "CloudFront HTTP version."
  type        = string
  default     = "http2"
}

variable "force_destroy" {
  description = "Whether to allow the site bucket to be force-destroyed."
  type        = bool
  default     = false
}

variable "enable_spa_fallback" {
  description = "Whether to rewrite 403 and 404 responses to index.html."
  type        = bool
  default     = true
}

variable "enable_pretty_urls" {
  description = "Whether to rewrite extensionless viewer requests to index.html paths."
  type        = bool
  default     = true
}

variable "basic_auth_enabled" {
  description = "Whether to require HTTP basic auth at the CloudFront viewer-request edge."
  type        = bool
  default     = false
}

variable "basic_auth_username" {
  description = "Basic-auth username when basic_auth_enabled is true."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = !var.basic_auth_enabled || var.basic_auth_username != null
    error_message = "basic_auth_username must be set when basic_auth_enabled is true."
  }
}

variable "basic_auth_password" {
  description = "Basic-auth password when basic_auth_enabled is true."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = !var.basic_auth_enabled || var.basic_auth_password != null
    error_message = "basic_auth_password must be set when basic_auth_enabled is true."
  }
}

variable "basic_auth_realm" {
  description = "Realm label returned in the WWW-Authenticate challenge."
  type        = string
  default     = "Restricted"
}

variable "tags" {
  description = "Additional tags to apply to created resources."
  type        = map(string)
  default     = {}
}
