variable "name" {
  description = "Name of the HTTP API."
  type        = string
}

variable "description" {
  description = "Description of the HTTP API."
  type        = string
  default     = null
}

variable "cors_configuration" {
  description = "CORS configuration for the API."
  type = object({
    allow_origins     = optional(list(string), [])
    allow_methods     = optional(list(string), [])
    allow_headers     = optional(list(string), [])
    expose_headers    = optional(list(string), [])
    max_age           = optional(number, 300)
    allow_credentials = optional(bool, false)
  })
  default = null
}

variable "routes" {
  description = <<-EOT
    Map of routes to create. Each key is a logical route identifier.

    `authorization_type` selects how the route is authorized and accepts `NONE`,
    `AWS_IAM`, or `JWT`. When left null it is derived from `authorizer_key`:
    `JWT` when an authorizer is referenced, `NONE` otherwise. `authorizer_key`
    may only be set for JWT routes.
  EOT
  type = map(object({
    route_key              = string
    lambda_function_arn    = string
    lambda_function_name   = string
    payload_format_version = optional(string, "2.0")
    authorizer_key         = optional(string, null)
    authorization_type     = optional(string, null)
    timeout_milliseconds   = optional(number, 29000)
  }))
  default = {}

  validation {
    condition = alltrue([
      for route in var.routes : contains(["NONE", "AWS_IAM", "JWT"], route.authorization_type)
      if route.authorization_type != null
    ])
    error_message = "Each route's authorization_type must be one of NONE, AWS_IAM, or JWT."
  }

  validation {
    condition = alltrue([
      for route in var.routes : route.authorizer_key != null
      if route.authorization_type == "JWT"
    ])
    error_message = "Routes with authorization_type JWT must reference a JWT authorizer via authorizer_key."
  }

  validation {
    condition = alltrue([
      for route in var.routes : route.authorizer_key == null
      if route.authorization_type != null && route.authorization_type != "JWT"
    ])
    error_message = "Routes with authorization_type NONE or AWS_IAM must not set authorizer_key."
  }
}

variable "jwt_authorizers" {
  description = "Map of JWT authorizers (e.g. a Coppice OIDC instance). Key is referenced by routes."
  type = map(object({
    issuer_url       = string
    audience         = list(string)
    identity_sources = optional(list(string), ["$request.header.Authorization"])
  }))
  default = {}
}

variable "stage_name" {
  description = "API Gateway stage name."
  type        = string
  default     = "$default"
}

variable "auto_deploy" {
  description = "Whether to auto-deploy changes to the stage."
  type        = bool
  default     = true
}

variable "create_access_log_group" {
  description = "Whether to create a CloudWatch log group for access logs."
  type        = bool
  default     = false
}

variable "access_log_format" {
  description = "Access log format string. Only used when create_access_log_group is true."
  type        = string
  default     = "$context.requestId $context.identity.sourceIp $context.requestTime $context.httpMethod $context.routeKey $context.status $context.responseLength"
}

variable "access_log_retention_days" {
  description = "CloudWatch log retention days for access logs."
  type        = number
  default     = 30
}

variable "custom_domain_name" {
  description = "Custom domain name for the API. Set to null to skip custom domain resources."
  type        = string
  default     = null
}

variable "custom_domain_certificate_arn" {
  description = "ACM certificate ARN for the custom domain. Required when custom_domain_name is set."
  type        = string
  default     = null
}

variable "route53_zone_id" {
  description = "Route 53 zone ID for the custom domain alias record. Required when custom_domain_name is set."
  type        = string
  default     = null
}

variable "api_mapping_key" {
  description = "API mapping key (path prefix) when custom_domain_name is set. Empty string maps to root."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
