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

variable "kms_key_arn" {
  description = "Optional existing KMS key ARN to use for bucket encryption. When omitted, the module creates a dedicated CMK."
  type        = string
  default     = null
}

variable "kms_key_policy_json" {
  description = "Optional explicit KMS key policy JSON to use when the module creates a dedicated CMK."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to apply to the certificate."
  type        = map(string)
  default     = {}
}
