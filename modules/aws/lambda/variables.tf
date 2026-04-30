variable "app_name" {
  description = "Application name prefix."
  type        = string
}

variable "deployment_environment" {
  description = "Deployment environment suffix."
  type        = string
}

variable "function_name" {
  description = "Logical function name."
  type        = string
}

variable "handler_name" {
  description = "Lambda handler name."
  type        = string
  default     = "index.handler"
}

variable "runtime" {
  description = "Lambda runtime."
  type        = string
  default     = "nodejs22.x"
}

variable "timeout" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 3
}

variable "memory_size" {
  description = "Lambda memory size in MB."
  type        = number
  default     = 128
}

variable "environment" {
  description = "Lambda environment variables."
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "Optional existing KMS key ARN to use for Lambda environment and secret encryption. When omitted, the module creates a dedicated CMK."
  type        = string
  default     = null
}

variable "kms_key_policy_json" {
  description = "Optional explicit KMS key policy JSON to use when the module creates a dedicated CMK."
  type        = string
  default     = null
}

variable "source_bucket_arn" {
  description = "ARN of deployment source bucket."
  type        = string
}

variable "source_bucket_id" {
  description = "Name or ID of deployment source bucket."
  type        = string
}

variable "source_object_key" {
  description = "Optional S3 object key for the deployment archive. Defaults to app_name-function_name.zip to preserve the existing doxchange contract."
  type        = string
  default     = null
}

variable "publish" {
  description = "Whether to publish a new function version on update."
  type        = bool
  default     = true
}

variable "tracing_mode" {
  description = "AWS X-Ray tracing mode for the Lambda function."
  type        = string
  default     = "Active"

  validation {
    condition     = contains(["Active", "PassThrough"], var.tracing_mode)
    error_message = "tracing_mode must be Active or PassThrough."
  }
}

variable "create_url" {
  description = "Whether to create a Lambda Function URL."
  type        = bool
  default     = false
}

variable "url_authorization_type" {
  description = "Auth type for Lambda Function URL when create_url is true."
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["AWS_IAM", "NONE"], var.url_authorization_type)
    error_message = "url_authorization_type must be NONE or AWS_IAM."
  }
}

variable "create_secret" {
  description = "Whether to create a Secrets Manager secret for the Lambda."
  type        = bool
  default     = false
}

variable "backend_user_name" {
  description = "Optional IAM user that should be able to manage the generated secret."
  type        = string
  default     = null
}

variable "s3_required_access" {
  description = "Optional extra S3 permissions keyed by a stable identifier."
  type = map(object({
    action    = string
    resources = list(string)
  }))
  default = {}
}

variable "additional_role_policy_arns" {
  description = "Optional existing IAM policy ARNs to attach to the Lambda execution role."
  type        = list(string)
  default     = []
}

variable "assume_role_services" {
  description = "AWS services allowed to assume the Lambda execution role. Include edgelambda.amazonaws.com when Lambda@Edge trust is required."
  type        = list(string)
  default     = ["lambda.amazonaws.com"]

  validation {
    condition     = contains(var.assume_role_services, "lambda.amazonaws.com")
    error_message = "assume_role_services must include lambda.amazonaws.com."
  }
}
