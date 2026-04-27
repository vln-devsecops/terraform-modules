variable "app_name" {
  description = "The name of the application."
  type        = string
}

variable "attributes" {
  description = "The attributes declared for the DynamoDB table and its indexes."
  type = list(object({
    name = string
    type = string
  }))
}

variable "deployment_environment" {
  description = "The deployment environment name such as dev, staging, or prod."
  type        = string
}

variable "function" {
  description = "The functional area served by this table, such as notifications or comments."
  type        = string
}

variable "hash_key" {
  description = "The partition key for the DynamoDB table."
  type        = string

  validation {
    condition     = contains([for attr in var.attributes : attr.name], var.hash_key)
    error_message = "The hash_key must be one of the attribute names defined in attributes."
  }
}

variable "global_secondary_indices" {
  description = "Global secondary indexes for the DynamoDB table."
  type = list(object({
    name               = string
    projection_type    = string
    hash_key           = string
    range_key          = string
    write_capacity     = optional(number)
    read_capacity      = optional(number)
    non_key_attributes = optional(list(string))
  }))
  default = []

  validation {
    condition = alltrue([
      for gsi in var.global_secondary_indices :
      contains([for attr in var.attributes : attr.name], gsi.hash_key) &&
      contains([for attr in var.attributes : attr.name], gsi.range_key)
    ])
    error_message = "Each global secondary index key must be declared in attributes."
  }
}

variable "local_secondary_indices" {
  description = "Local secondary indexes for the DynamoDB table."
  type = list(object({
    name               = string
    projection_type    = string
    range_key          = string
    non_key_attributes = optional(list(string))
  }))
  default = []

  validation {
    condition = alltrue([
      for lsi in var.local_secondary_indices :
      contains([for attr in var.attributes : attr.name], lsi.range_key)
    ])
    error_message = "Each local secondary index range_key must be declared in attributes."
  }
}

variable "kms_key_arn" {
  description = "Optional existing KMS key ARN to use for table encryption. When omitted, the module creates a dedicated CMK."
  type        = string
  default     = null
}

variable "kms_key_policy_json" {
  description = "Optional explicit KMS key policy JSON to use when the module creates a dedicated CMK."
  type        = string
  default     = null
}

variable "range_key" {
  description = "The sort key for the DynamoDB table."
  type        = string

  validation {
    condition     = contains([for attr in var.attributes : attr.name], var.range_key)
    error_message = "The range_key must be one of the attribute names defined in attributes."
  }
}

variable "ro_user_name" {
  description = "Optional IAM user name to grant read-only table access."
  type        = string
  default     = null
}

variable "rw_user_name" {
  description = "Optional IAM user name to grant read-write table access."
  type        = string
  default     = null
}

variable "short_deployment_region" {
  description = "Short region identifier used in the table name, such as useast1 or euwest1."
  type        = string
}
