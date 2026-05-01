variable "deployment_environment" {
  description = "Deployment environment name such as dev, staging, or prod."
  type        = string
  default     = "prod"
}

variable "app_name" {
  description = "Application name prefix."
  type        = string
  default     = "sampleapp"
}

variable "source_bucket_arn" {
  description = "ARN of the S3 bucket (in us-east-1) that stores the deployment archive."
  type        = string
  default     = "arn:aws:s3:::deployment-sampleapp-us-east-1"
}

variable "source_bucket_id" {
  description = "Name of the S3 bucket that stores the deployment archive."
  type        = string
  default     = "deployment-sampleapp-us-east-1"
}

variable "frontend_bucket_arn" {
  description = "ARN of the S3 bucket containing the frontend assets the function serves."
  type        = string
  default     = "arn:aws:s3:::frontend-sampleapp"
}
