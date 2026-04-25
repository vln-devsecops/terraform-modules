variable "app_name" {
  description = "Name of the application being deployed."
  type        = string
  default     = "exampleapp"
}

variable "deployment_environment" {
  description = "Deployment environment name such as dev, staging, or prod."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for the example deployment."
  type        = string
  default     = "us-east-1"
}
