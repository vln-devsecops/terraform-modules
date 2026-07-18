variable "app_name" {
  description = "Application name prefix, used to derive resource names."
  type        = string
}

variable "deployment_environment" {
  description = "Deployment environment suffix (e.g. dev, staging, prod)."
  type        = string
}

variable "admin_allowed_principal_arns" {
  description = "IAM principal ARNs (users or roles) granted lambda:InvokeFunctionUrl on the admin Function URL via a resource-based policy. AWS_IAM auth alone does not implicitly grant any caller invoke access -- each principal that should be able to poll/manage submissions must be listed here."
  type        = list(string)
  default     = []
}

variable "submit_cors" {
  description = <<-EOT
    Optional CORS configuration for the public submit Function URL, answered
    directly by AWS at the Function URL layer without invoking the Lambda.
    Omit (the default) to leave CORS entirely unset -- the browser gets no
    Access-Control-* headers, so cross-origin callers are blocked by default.
    Set this to the consuming site's own origin(s) when the contact form is
    submitted from a different origin than this Function URL's own domain.
  EOT
  type = object({
    allow_credentials = optional(bool)
    allow_headers     = optional(list(string))
    allow_methods     = optional(list(string))
    allow_origins     = optional(list(string))
    expose_headers    = optional(list(string))
    max_age           = optional(number)
  })
  default = null
}

variable "submit_timeout" {
  description = "Timeout in seconds for the public submit Lambda."
  type        = number
  default     = 5
}

variable "admin_timeout" {
  description = "Timeout in seconds for the AWS_IAM-authorized admin Lambda."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Additional tags to apply to all resources this module creates."
  type        = map(string)
  default     = {}
}
