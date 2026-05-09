variable "region" {
  description = "AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "source_bucket_name" {
  description = "Name for the source S3 bucket."
  type        = string
  default     = "example-source-bucket-rlc"
}

variable "destination_bucket_name" {
  description = "Name for the destination S3 bucket."
  type        = string
  default     = "example-destination-bucket-rlc"
}
