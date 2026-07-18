variable "aws_region" {
  description = "AWS region for provider-backed resources."
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Application name prefix."
  type        = string
  default     = "example-app"
}

variable "deployment_environment" {
  description = "Deployment environment suffix."
  type        = string
  default     = "dev"
}

variable "admin_allowed_principal_arns" {
  description = "IAM principal ARNs granted lambda:InvokeFunctionUrl on the admin Function URL."
  type        = list(string)
  default     = ["arn:aws:iam::123456789012:user/example"]
}

variable "submit_allowed_origins" {
  description = "Origins allowed to POST to the public submit Function URL."
  type        = list(string)
  default     = ["https://example.com"]
}
