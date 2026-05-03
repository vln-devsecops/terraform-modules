variable "aws_region" {
  description = "AWS region to deploy the live test resources."
  type        = string
  default     = "us-east-1"
}

variable "name_suffix" {
  description = "Random suffix to ensure test resource names are unique across concurrent runs."
  type        = string
}
