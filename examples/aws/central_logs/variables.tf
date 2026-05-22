variable "aws_region" {
  description = "AWS region for the example deployment."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "S3 bucket name for the central logs bucket."
  type        = string
  default     = "example-org-central-logs"
}

variable "allowed_account_ids" {
  description = "AWS account IDs allowed to write logs cross-account."
  type        = list(string)
  default     = ["123456789012"]
}

variable "enable_cloudtrail" {
  description = "Whether to create a multi-region CloudTrail trail."
  type        = bool
  default     = false
}

variable "deployment_mode" {
  description = "Deployment mode for the central logs module: central or client."
  type        = string
  default     = "central"
}
