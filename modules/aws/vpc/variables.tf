variable "app_name" {
  description = "Application name. Used as a tag value on all resources."
  type        = string
}

variable "deployment_environment" {
  description = "Deployment environment (e.g. dev, staging, prod). Used as a tag value on all resources."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets. One subnet is created per entry, assigned to availability zones in round-robin order."
  type        = list(string)
  default     = ["10.0.1.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) > 0
    error_message = "At least one public subnet CIDR must be provided."
  }

  validation {
    condition     = alltrue([for cidr in var.public_subnet_cidrs : can(cidrnetmask(cidr))])
    error_message = "All entries in public_subnet_cidrs must be valid CIDR blocks."
  }
}

variable "availability_zones" {
  description = "Explicit list of availability zone names to assign to subnets. When empty, the module queries the current region for available zones."
  type        = list(string)
  default     = []
}

variable "enable_dns_support" {
  description = "Enable DNS resolution within the VPC."
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames for instances launched into the VPC."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}
