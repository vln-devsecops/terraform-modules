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
      web_acl_id                     = null
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

  assert {
    condition     = length(aws_s3_object.placeholder_index) == 1 && aws_s3_object.placeholder_index[0].key == "index.html"
    error_message = "Placeholder index object should exist by default."
  }

  assert {
    condition     = length(aws_s3_object.placeholder_404) == 1 && aws_s3_object.placeholder_404[0].key == "404.html"
    error_message = "Placeholder 404 object should exist by default."
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

run "explicit_custom_error_responses_override_spa_fallback" {
  command = plan

  variables {
    site_name           = "test-explicit.devsecops.vlinder.ca"
    route53_zone_id     = "Z1234567890"
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/example"
    enable_spa_fallback = true # should be ignored when custom_error_responses is set
    custom_error_responses = [
      {
        error_code         = 404
        response_code      = 404
        response_page_path = "/404.html"
      }
    ]
  }

  assert {
    condition     = length(aws_cloudfront_distribution.site.custom_error_response) == 1
    error_message = "Explicit custom_error_responses should override enable_spa_fallback."
  }

  assert {
    condition     = one([for r in aws_cloudfront_distribution.site.custom_error_response : r if r.error_code == 404]).response_page_path == "/404.html"
    error_message = "Custom error response page path should be /404.html."
  }
}

run "waf_acl_and_access_logging_are_applied" {
  command = plan

  variables {
    site_name                  = "test-waf.devsecops.vlinder.ca"
    route53_zone_id            = "Z1234567890"
    acm_certificate_arn        = "arn:aws:acm:us-east-1:123456789012:certificate/example"
    waf_web_acl_arn            = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/test/abc"
    access_log_bucket          = "my-logs.s3.amazonaws.com"
    access_log_prefix          = "cf-access/"
    response_headers_policy_id = "67f7725c-6f97-4210-82d7-5512b31e9d03"
  }

  assert {
    condition     = aws_cloudfront_distribution.site.web_acl_id == "arn:aws:wafv2:us-east-1:123456789012:global/webacl/test/abc"
    error_message = "WAF web ACL ARN should be applied to the CloudFront distribution."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.site.logging_config) == 1
    error_message = "Access logging config should be set when access_log_bucket is provided."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.site.logging_config).bucket == "my-logs.s3.amazonaws.com"
    error_message = "Access log bucket should match the provided value."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.site.default_cache_behavior).response_headers_policy_id == "67f7725c-6f97-4210-82d7-5512b31e9d03"
    error_message = "Response headers policy ID should be applied to the default cache behavior."
  }
}

run "custom_placeholder_html_is_applied" {
  command = plan

  variables {
    site_name              = "test-custom-placeholder.devsecops.vlinder.ca"
    route53_zone_id        = "Z1234567890"
    acm_certificate_arn    = "arn:aws:acm:us-east-1:123456789012:certificate/example"
    placeholder_index_html = "<html><body>custom index</body></html>"
    placeholder_404_html   = "<html><body>custom 404</body></html>"
  }

  assert {
    condition     = aws_s3_object.placeholder_index[0].content == "<html><body>custom index</body></html>"
    error_message = "placeholder_index_html should set the placeholder index object content."
  }

  assert {
    condition     = aws_s3_object.placeholder_404[0].content == "<html><body>custom 404</body></html>"
    error_message = "placeholder_404_html should set the placeholder 404 object content."
  }
}

run "null_placeholder_html_uses_module_defaults" {
  command = plan

  variables {
    site_name           = "test-null-placeholder.devsecops.vlinder.ca"
    route53_zone_id     = "Z1234567890"
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/example"
  }

  assert {
    condition     = strcontains(aws_s3_object.placeholder_index[0].content, "Site Placeholder")
    error_message = "Default placeholder index HTML should be used when placeholder_index_html is null."
  }

  assert {
    condition     = strcontains(aws_s3_object.placeholder_404[0].content, "404 Not Found")
    error_message = "Default placeholder 404 HTML should be used when placeholder_404_html is null."
  }
}

run "placeholder_seeding_can_be_disabled" {
  command = plan

  variables {
    site_name               = "test-no-placeholder.devsecops.vlinder.ca"
    route53_zone_id         = "Z1234567890"
    acm_certificate_arn     = "arn:aws:acm:us-east-1:123456789012:certificate/example"
    create_placeholder_site = false
  }

  assert {
    condition     = length(aws_s3_object.placeholder_index) == 0 && length(aws_s3_object.placeholder_404) == 0
    error_message = "Placeholder objects should not be created when create_placeholder_site is false."
  }
}
