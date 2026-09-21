variable "name_suffix" {
  description = "Unique suffix appended to the integration fixture resources."
  type        = string
}

variable "aws_region" {
  description = "AWS region for the integration fixture."
  type        = string
  default     = "us-east-1"
}
