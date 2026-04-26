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

variable "app_name" {
  description = "Application name prefix for the example Lambda."
  type        = string
  default     = "sampleapp"
}

variable "function_name" {
  description = "Function name for the example Lambda."
  type        = string
  default     = "api"
}

variable "source_bucket_arn" {
  description = "ARN of the S3 bucket that stores the deployment archive."
  type        = string
  default     = "arn:aws:s3:::deployment-sampleapp"
}

variable "source_bucket_id" {
  description = "Name of the S3 bucket that stores the deployment archive."
  type        = string
  default     = "deployment-sampleapp"
}

variable "source_object_key" {
  description = "S3 object key for the deployment archive."
  type        = string
  default     = "lambdas/api/release.zip"
}
