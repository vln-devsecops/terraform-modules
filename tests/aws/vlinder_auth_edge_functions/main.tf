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

# Deliberately bare: no distribution, no S3 origin, no Cognito -- just the
# two CloudFront Function objects themselves, unassociated and unpublished
# (DEVELOPMENT stage only). This is a live-runtime smoke test for
# cloudfront-js-2.0 compatibility, not a deployment. See README.md for why
# it exists: a CloudFront Function that fails to parse (e.g. ES2020+ syntax
# such as `?.`/`??`, which cloudfront-js-2.0 rejects) causes CloudFront to
# serve a silent 503 to every viewer request through the associated
# behavior, with no log and no Lambda invocation pointing at the cause --
# terraform test's mock provider can never catch that, only a real
# `aws cloudfront test-function` call can.
#
# `code` reads templates/dist/*.js -- the exact generated files
# modules/aws/vlinder_auth/main.tf itself deploys via file() -- not a copy,
# so this suite exercises production's actual compiled output.
resource "aws_cloudfront_function" "admin_api_rewrite" {
  name    = "vlinder-auth-edge-smoke-admin-api-${var.name_suffix}"
  runtime = "cloudfront-js-2.0"
  publish = false # DEVELOPMENT stage only -- this is a smoke test, never needs to go LIVE
  comment = "Live runtime smoke test (see tests/aws/vlinder_auth_edge_functions/), not a real deployment"
  code    = file("${path.module}/../../../modules/aws/vlinder_auth/templates/dist/admin_api_rewrite.js")
}

resource "aws_cloudfront_function" "spa_viewer_request" {
  name    = "vlinder-auth-edge-smoke-spa-vr-${var.name_suffix}"
  runtime = "cloudfront-js-2.0"
  publish = false
  comment = "Live runtime smoke test (see tests/aws/vlinder_auth_edge_functions/), not a real deployment"
  code    = file("${path.module}/../../../modules/aws/vlinder_auth/templates/dist/spa_viewer_request.js")
}

output "admin_api_rewrite_function_name" {
  value = aws_cloudfront_function.admin_api_rewrite.name
}

output "spa_viewer_request_function_name" {
  value = aws_cloudfront_function.spa_viewer_request.name
}
