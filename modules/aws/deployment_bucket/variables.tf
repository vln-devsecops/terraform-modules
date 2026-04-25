variable "app_name" {
  description = "Name of the application being deployed."
  type        = string
}

variable "deployment_environment" {
  description = "Deployment environment name such as dev, staging, or prod."
  type        = string
}

variable "deployment_region" {
  description = "Provider region identifier used in the bucket name."
  type        = string
}
