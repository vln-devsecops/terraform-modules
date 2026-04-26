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

variable "source_bucket_arn" {
  description = "ARN of the deployment source bucket."
  type        = string
  default     = "arn:aws:s3:::deployment-sampleapp"
}

variable "source_bucket_id" {
  description = "Name of the deployment source bucket."
  type        = string
  default     = "deployment-sampleapp"
}

variable "frontend_bucket_arn" {
  description = "ARN of the frontend bucket used in the compatibility fixture."
  type        = string
  default     = "arn:aws:s3:::frontend-sampleapp"
}

variable "backend_user_name" {
  description = "IAM user that should receive the generated secret policy."
  type        = string
  default     = "backend-user"
}
