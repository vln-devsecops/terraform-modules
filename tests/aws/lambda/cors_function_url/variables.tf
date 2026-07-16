variable "deployment_environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for the fixture."
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Application name prefix."
  type        = string
  default     = "sampleapp"
}

variable "name_suffix" {
  description = "Unique suffix appended to the fixture's resources."
  type        = string
}

variable "allowed_origin" {
  description = "Origin to allow via CORS, exercised end-to-end by run.sh."
  type        = string
  default     = "https://example.com"
}
