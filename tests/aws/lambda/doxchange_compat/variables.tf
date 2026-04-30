variable "deployment_environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for the compatibility fixture."
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Application name prefix."
  type        = string
  default     = "sampleapp"
}

variable "name_suffix" {
  description = "Unique suffix appended to the compatibility fixture resources."
  type        = string
}
