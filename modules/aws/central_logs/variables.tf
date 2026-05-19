variable "bucket_name" {
  description = "S3 bucket name for central logs."
  type        = string
}

variable "allowed_account_ids" {
  description = "AWS account IDs allowed to write logs into the bucket via cross-account PutObject."
  type        = list(string)
}

variable "create_kms_key" {
  description = "Whether to create a KMS key for bucket encryption. When false, SSE-S3 (AES256) is used."
  type        = bool
  default     = true
}

variable "kms_key_deletion_window_days" {
  description = "Waiting period in days before KMS key deletion (7–30)."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window_days >= 7 && var.kms_key_deletion_window_days <= 30
    error_message = "kms_key_deletion_window_days must be between 7 and 30."
  }
}

variable "standard_retention_days" {
  description = "Days to keep objects in S3 Standard before transitioning to Glacier Instant Retrieval."
  type        = number
  default     = 90
}

variable "glacier_retention_years" {
  description = "Years to retain objects in Glacier Instant Retrieval before expiry. Total lifecycle = standard_retention_days + glacier_retention_years * 365."
  type        = number
  default     = 7
}

variable "enable_cloudtrail" {
  description = "Whether to create a multi-region CloudTrail trail delivering to this bucket."
  type        = bool
  default     = false
}

variable "cloudtrail_name" {
  description = "Name for the CloudTrail trail. Only used when enable_cloudtrail = true."
  type        = string
  default     = "central-logs-trail"
}

variable "tags" {
  description = "Additional tags to apply to all taggable resources."
  type        = map(string)
  default     = {}
}

variable "deployment_mode" {
  description = "Deployment mode for the central_logs module. Allowed values: 'central', 'client'."
  type        = string
  validation {
    condition     = contains(["central", "client"], var.deployment_mode)
    error_message = "deployment_mode must be one of: central, client."
  }
}

# Guardrail: Forbid enable_cloudtrail=true when deployment_mode=client
locals {
  _cloudtrail_client_mode_invalid = var.deployment_mode == "client" && var.enable_cloudtrail
}

check "cloudtrail_client_mode_incompatible" {
  assert {
    condition     = !local._cloudtrail_client_mode_invalid
    error_message = "enable_cloudtrail cannot be true when deployment_mode is 'client'."
  }
}
