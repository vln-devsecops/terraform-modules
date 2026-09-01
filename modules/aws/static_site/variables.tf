variable "site_name" {
  description = "Fully qualified hostname for the static site (used for CloudFront alias and resource naming)."
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket name for the static site content. If not provided, defaults to site_name."
  type        = string
  default     = ""
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

variable "pretty_url_exceptions" {
  description = "Exact request URIs (e.g. \"/LICENSE\") to exclude from the enable_pretty_urls rewrite, for extensionless static files that are not pretty-url routes."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for uri in var.pretty_url_exceptions : startswith(uri, "/")])
    error_message = "pretty_url_exceptions entries must be absolute URIs starting with \"/\", e.g. \"/LICENSE\"."
  }
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

variable "access_log_bucket" {
  description = "S3 bucket domain name for CloudFront access logs. Set to enable access logging."
  type        = string
  default     = null
}

variable "access_log_prefix" {
  description = "Prefix for CloudFront access log objects."
  type        = string
  default     = ""
}

variable "waf_web_acl_arn" {
  description = "ARN of a WAF web ACL to associate with the CloudFront distribution. Must be in us-east-1."
  type        = string
  default     = null
}

variable "custom_error_responses" {
  description = "Explicit custom error response rules. When set, overrides enable_spa_fallback. Each entry maps an HTTP error code to a response."
  type = list(object({
    error_code            = number
    response_code         = number
    response_page_path    = string
    error_caching_min_ttl = optional(number, 300)
  }))
  default = null
}

variable "response_headers_policy_id" {
  description = "CloudFront managed or custom response headers policy ID to attach to the default cache behavior. Mutually exclusive with enable_noindex."
  type        = string
  default     = null
}

variable "enable_noindex" {
  description = "Whether to attach an X-Robots-Tag: noindex, nofollow response header to the default cache behavior, e.g. for non-prod sites with an unguessable hostname. Mutually exclusive with response_headers_policy_id."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_noindex || var.response_headers_policy_id == null
    error_message = "enable_noindex and response_headers_policy_id are mutually exclusive: a caller-supplied response headers policy already has full control over headers, so add the X-Robots-Tag header to it directly instead."
  }
}

variable "origin_response_lambda_qualified_arn" {
  description = "Qualified ARN (including a numeric version, not an alias) of a Lambda@Edge function in us-east-1 to associate with the origin-response event on the default cache behavior. Pair with the aws/lambda-at-edge module to build the function; this module only wires the association and has no opinion on what the function does. Leave null (the default) to omit any origin-response association."
  type        = string
  default     = null

  validation {
    condition = var.origin_response_lambda_qualified_arn == null || can(regex(
      "^arn:aws:lambda:us-east-1:[0-9]{12}:function:[a-zA-Z0-9-_]+:[0-9]+$",
      var.origin_response_lambda_qualified_arn
    ))
    error_message = "origin_response_lambda_qualified_arn must be a qualified Lambda@Edge ARN in us-east-1, ending in a numeric version (not an alias or an unqualified function ARN), e.g. arn:aws:lambda:us-east-1:123456789012:function:origin-response:3."
  }
}

variable "create_placeholder_site" {
  description = "Whether to create placeholder objects for `default_root_object` and `404.html` so the site is testable before first content deployment."
  type        = bool
  default     = true
}

variable "placeholder_index_html" {
  description = "HTML content for the placeholder default_root_object when create_placeholder_site is true. Defaults to null, which uses the module's built-in placeholder page."
  type        = string
  default     = null
}

variable "placeholder_404_html" {
  description = "HTML content for the placeholder 404.html object when create_placeholder_site is true. Defaults to null, which uses the module's built-in placeholder page."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to apply to created resources."
  type        = map(string)
  default     = {}
}
