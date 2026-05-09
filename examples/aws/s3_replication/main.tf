terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "source" {
  bucket        = var.source_bucket_name
  force_destroy = true
  tags = {
    Name = "source-bucket"
  }
}

resource "aws_s3_bucket" "destination" {
  bucket        = var.destination_bucket_name
  force_destroy = true
  tags = {
    Name = "destination-bucket"
  }
}

module "s3_replication" {
  source = "../../../modules/aws/s3_replication"

  source_bucket_id       = aws_s3_bucket.source.id
  source_bucket_arn      = aws_s3_bucket.source.arn
  destination_bucket_arn = aws_s3_bucket.destination.arn
  role_name              = "example-s3-log-replication"
  rule_id                = "replicate-example-logs"
  tags = {
    Environment = "example"
  }
}

