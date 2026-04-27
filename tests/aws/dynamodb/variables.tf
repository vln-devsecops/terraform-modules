variable "app_name" {
  description = "Base application name prefix for the integration fixture."
  type        = string
  default     = "integrationapp"
}

variable "deployment_environment" {
  description = "Deployment environment name used for the integration fixture."
  type        = string
  default     = "int"
}

variable "aws_region" {
  description = "AWS region for the integration fixture."
  type        = string
  default     = "us-east-1"
}

variable "short_deployment_region" {
  description = "Short region identifier used in the table name."
  type        = string
  default     = "useast1"
}

variable "function" {
  description = "Base functional area name for the integration fixture."
  type        = string
  default     = "events"
}

variable "name_suffix" {
  description = "Unique suffix appended to the integration fixture resources."
  type        = string
}
