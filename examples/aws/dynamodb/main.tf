terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "dynamodb" {
  source = "../../../modules/aws/dynamodb"

  app_name                = var.app_name
  deployment_environment  = var.deployment_environment
  short_deployment_region = var.short_deployment_region
  function                = var.function
  hash_key                = "pk"
  range_key               = "sk"
  attributes = [
    {
      name = "pk"
      type = "S"
    },
    {
      name = "sk"
      type = "S"
    },
  ]
  global_secondary_indices = []
  local_secondary_indices  = []
}

output "table_name" {
  value = module.dynamodb.table_name
}
