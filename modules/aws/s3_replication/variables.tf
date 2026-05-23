variable "source_bucket_id" {
  description = "ID (name) of the source S3 bucket to replicate from."
  type        = string
}

variable "source_bucket_arn" {
  description = "ARN of the source S3 bucket to replicate from."
  type        = string
}

variable "destination_bucket_arn" {
  description = "ARN of the destination S3 bucket to replicate logs to."
  type        = string
}

variable "role_name" {
  description = "Name for the IAM replication role."
  type        = string
}

variable "rule_id" {
  description = "Identifier for the S3 replication rule."
  type        = string
  default     = "replicate-to-central-logs"
}

variable "destination_storage_class" {
  description = "S3 storage class used in the replication destination."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "REDUCED_REDUNDANCY", "STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER", "DEEP_ARCHIVE", "GLACIER_IR"], var.destination_storage_class)
    error_message = "destination_storage_class must be a valid S3 storage class."
  }
}

variable "manage_source_bucket_versioning" {
  description = "Whether this module should manage versioning on the source bucket. Set to false when another module already owns source bucket versioning."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to taggable resources."
  type        = map(string)
  default     = {}
}
