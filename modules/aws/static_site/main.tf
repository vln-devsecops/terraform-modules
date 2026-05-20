locals {
  common_tags = merge(var.tags, {
    site = var.site_name
  })
  viewer_request_code = templatefile("${path.module}/templates/viewer_request.js.tftpl", {
    basic_auth_enabled = var.basic_auth_enabled ? "true" : "false"
    basic_auth_header  = var.basic_auth_enabled ? base64encode("${var.basic_auth_username}:${var.basic_auth_password}") : ""
    basic_auth_realm   = var.basic_auth_realm
    enable_pretty_urls = var.enable_pretty_urls ? "true" : "false"
  })
  effective_custom_error_responses = var.custom_error_responses != null ? var.custom_error_responses : (
    var.enable_spa_fallback ? [
      { error_code = 403, response_code = 200, response_page_path = "/${var.default_root_object}", error_caching_min_ttl = 300 },
      { error_code = 404, response_code = 200, response_page_path = "/${var.default_root_object}", error_caching_min_ttl = 300 },
    ] : []
  )
}

# trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket" "site" {
  bucket        = var.site_name
  force_destroy = var.force_destroy
  tags          = merge(local.common_tags, { rg = "storage" })
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${replace(var.site_name, ".", "-")}-oac"
  description                       = "Origin access control for ${var.site_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "viewer_request" {
  name    = "${replace(var.site_name, ".", "-")}-viewer-request"
  runtime = "cloudfront-js-2.0"
  publish = true
  comment = "Viewer-request handling for ${var.site_name}"
  code    = local.viewer_request_code
}

data "aws_iam_policy_document" "site_cloudfront_read" {
  version = "2012-10-17"

  statement {
    sid       = "AllowCloudFrontRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_cloudfront_read.json
}

# trivy:ignore:AVD-AWS-0011
resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  aliases             = [var.site_name]
  default_root_object = var.default_root_object
  is_ipv6_enabled     = true
  http_version        = var.http_version
  price_class         = var.cloudfront_price_class
  web_acl_id          = var.waf_web_acl_arn

  origin {
    domain_name                 = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                   = "StaticSite"
    origin_access_control_id    = aws_cloudfront_origin_access_control.site.id
    response_completion_timeout = 0
  }

  default_cache_behavior {
    target_origin_id           = "StaticSite"
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true
    response_headers_policy_id = var.response_headers_policy_id

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.viewer_request.arn
    }
  }

  dynamic "logging_config" {
    for_each = var.access_log_bucket != null ? [1] : []
    content {
      bucket          = var.access_log_bucket
      prefix          = var.access_log_prefix
      include_cookies = false
    }
  }

  dynamic "custom_error_response" {
    for_each = { for i, v in local.effective_custom_error_responses : i => v }

    content {
      error_code            = custom_error_response.value.error_code
      response_code         = custom_error_response.value.response_code
      response_page_path    = custom_error_response.value.response_page_path
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  tags = merge(local.common_tags, { rg = "compute" })
}

resource "aws_route53_record" "site_a" {
  zone_id = var.route53_zone_id
  name    = var.site_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "site_aaaa" {
  zone_id = var.route53_zone_id
  name    = var.site_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}
