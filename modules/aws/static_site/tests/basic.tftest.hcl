mock_provider "aws" {
  override_during = plan

  mock_resource "aws_cloudfront_function" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:function/test"
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      id                             = "EDFDVBD632BHDS5"
      arn                            = "arn:aws:cloudfront::123456789012:distribution/EDFDVBD632BHDS5"
      domain_name                    = "d111111abcdef8.cloudfront.net"
      hosted_zone_id                 = "Z2FDTNDATAQYW2"
      status                         = "Deployed"
      etag                           = "test"
      in_progress_validation_batches = 0
    }
  }
}

run "static_site_defaults_match_contract" {
  command = plan

  variables {
    site_name           = "dashboard-4f8k2m1q9z.devsecops.vlinder.ca"
    route53_zone_id     = "Z1234567890"
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/example"
  }

  assert {
    condition     = aws_s3_bucket.site.bucket == "dashboard-4f8k2m1q9z.devsecops.vlinder.ca"
    error_message = "Static-site bucket naming changed unexpectedly."
  }

  assert {
    condition     = output.site_url == "https://dashboard-4f8k2m1q9z.devsecops.vlinder.ca"
    error_message = "Primary site URL output changed unexpectedly."
  }

  assert {
    condition     = aws_cloudfront_distribution.site.default_root_object == "index.html" && aws_cloudfront_distribution.site.price_class == "PriceClass_100"
    error_message = "CloudFront defaults changed unexpectedly."
  }

  assert {
    condition = length(aws_cloudfront_distribution.site.custom_error_response) == 2 && alltrue([
      for response in aws_cloudfront_distribution.site.custom_error_response :
      response.response_code == 200 && response.response_page_path == "/index.html"
    ])
    error_message = "SPA fallback behavior changed unexpectedly."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.site.block_public_acls && aws_s3_bucket_public_access_block.site.block_public_policy && aws_s3_bucket_public_access_block.site.ignore_public_acls && aws_s3_bucket_public_access_block.site.restrict_public_buckets
    error_message = "Public access block defaults changed unexpectedly."
  }

  assert {
    condition     = aws_route53_record.site_a.alias[0].name == "d111111abcdef8.cloudfront.net" && aws_route53_record.site_aaaa.zone_id == "Z1234567890"
    error_message = "Route53 alias record contract changed unexpectedly."
  }
}

run "optional_basic_auth_is_rendered_at_edge" {
  command = plan

  variables {
    site_name           = "dashboard-locked.devsecops.vlinder.ca"
    route53_zone_id     = "Z1234567890"
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/example"
    basic_auth_enabled  = true
    basic_auth_username = "dashboard"
    basic_auth_password = "super-secret"
    basic_auth_realm    = "Dashboard"
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.viewer_request.code, "www-authenticate")
    error_message = "Viewer-request function should include a basic-auth challenge when enabled."
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.viewer_request.code, "Basic ZGFzaGJvYXJkOnN1cGVyLXNlY3JldA==")
    error_message = "Viewer-request function should include the rendered basic-auth credential when enabled."
  }

  assert {
    condition     = aws_cloudfront_function.viewer_request.name == "dashboard-locked-devsecops-vlinder-ca-viewer-request"
    error_message = "Viewer-request function naming changed unexpectedly."
  }
}
