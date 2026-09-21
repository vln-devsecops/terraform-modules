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

# Deliberately bare: no distribution, no S3 origin, no ACM cert, no Route53
# record -- just two CloudFront Function objects, unassociated and
# unpublished (DEVELOPMENT stage only). This is a live-runtime smoke test
# for cloudfront-js-2.0 compatibility, not a deployment. See README.md for
# why it exists.
#
# Unlike modules/aws/vlinder_auth's two edge functions (committed, static
# templates/dist/*.js build artifacts), modules/aws/static_site's single
# viewer_request function is rendered from a real Terraform *template*
# (templates/viewer_request.js.tftpl) whose ${...} interpolations depend on
# module input variables -- there is no single static file to deploy here.
# So this suite renders two representative variants of the same
# templatefile() call modules/aws/static_site/main.tf itself makes, to
# exercise both branches of both conditionals (basic auth on/off, pretty
# URLs on/off) against the real cloudfront-js-2.0 runtime.
locals {
  edge_function_variants = {
    both_enabled = {
      basic_auth_enabled    = true
      basic_auth_username   = "smoketest"
      basic_auth_password   = "smoke-test-password"
      basic_auth_realm      = "Smoke Test"
      enable_pretty_urls    = true
      pretty_url_exceptions = ["/healthz"]
    }
    both_disabled = {
      basic_auth_enabled    = false
      basic_auth_username   = null
      basic_auth_password   = null
      basic_auth_realm      = "Restricted"
      enable_pretty_urls    = false
      pretty_url_exceptions = []
    }
  }

  # Same templatefile() call shape (and the same basic_auth_header /
  # pretty_url_exceptions derivations) as
  # modules/aws/static_site/main.tf's `local.viewer_request_code`, just
  # driven by the two variant configs above instead of the module's own
  # variables -- so this suite tests the real rendering logic, not a
  # simplified approximation of it.
  viewer_request_code = {
    for variant_name, variant in local.edge_function_variants :
    variant_name => templatefile("${path.module}/../../../modules/aws/static_site/templates/viewer_request.js.tftpl", {
      basic_auth_enabled    = variant.basic_auth_enabled ? "true" : "false"
      basic_auth_header     = variant.basic_auth_enabled ? base64encode("${variant.basic_auth_username}:${variant.basic_auth_password}") : ""
      basic_auth_realm      = variant.basic_auth_realm
      enable_pretty_urls    = variant.enable_pretty_urls ? "true" : "false"
      pretty_url_exceptions = jsonencode(variant.pretty_url_exceptions)
    })
  }
}

resource "aws_cloudfront_function" "viewer_request" {
  for_each = local.edge_function_variants

  name    = "static-site-edge-smoke-${replace(each.key, "_", "-")}-${var.name_suffix}"
  runtime = "cloudfront-js-2.0"
  publish = false # DEVELOPMENT stage only -- this is a smoke test, never needs to go LIVE
  comment = "Live runtime smoke test (see tests/aws/static_site_edge_function/), not a real deployment"
  code    = local.viewer_request_code[each.key]
}

output "viewer_request_function_names" {
  description = "Map of variant name (both_enabled, both_disabled) to the deployed CloudFront Function name."
  value       = { for variant_name, fn in aws_cloudfront_function.viewer_request : variant_name => fn.name }
}
