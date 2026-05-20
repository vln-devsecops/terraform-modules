mock_provider "aws" {
  override_during = plan

  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/example"
      domain_validation_options = [
        {
          domain_name           = "example.com"
          resource_record_name  = "_abc123.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_def456.acm.amazonaws.com."
        },
        {
          domain_name           = "*.example.com"
          resource_record_name  = "_abc123.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_def456.acm.amazonaws.com."
        }
      ]
      status = "PENDING_VALIDATION"
    }
  }

  mock_resource "aws_route53_record" {
    defaults = {
      fqdn = "_abc123.example.com"
    }
  }

  mock_resource "aws_acm_certificate_validation" {
    defaults = {}
  }
}

run "single_domain_creates_certificate_and_validation_records" {
  command = plan

  variables {
    domain_name     = "example.com"
    route53_zone_id = "Z1234567890ABC"
  }

  assert {
    condition     = aws_acm_certificate.this.domain_name == "example.com"
    error_message = "Certificate primary domain name does not match input."
  }

  assert {
    condition     = aws_acm_certificate.this.validation_method == "DNS"
    error_message = "Validation method should default to DNS."
  }

  assert {
    condition     = length(aws_route53_record.validation) == 1
    error_message = "Expected exactly one Route 53 validation record when ACM returns duplicate apex/wildcard validation records."
  }

  assert {
    condition     = length(aws_acm_certificate_validation.this) == 1
    error_message = "Expected one aws_acm_certificate_validation resource when wait_for_validation defaults to true."
  }

  assert {
    condition     = output.certificate_arn == "arn:aws:acm:us-east-1:123456789012:certificate/example"
    error_message = "certificate_arn output does not match expected ARN."
  }

  assert {
    condition     = output.certificate_domain_name == "example.com"
    error_message = "certificate_domain_name output does not match input domain."
  }

  assert {
    condition     = length(output.validation_record_fqdns) == 1
    error_message = "validation_record_fqdns output should contain one entry."
  }
}

run "wildcard_san_is_included_in_certificate" {
  command = plan

  variables {
    domain_name       = "example.com"
    subject_alt_names = ["*.example.com"]
    route53_zone_id   = "Z1234567890ABC"
  }

  assert {
    condition     = aws_acm_certificate.this.domain_name == "example.com"
    error_message = "Primary domain name should be example.com."
  }

  assert {
    condition     = contains(aws_acm_certificate.this.subject_alternative_names, "*.example.com")
    error_message = "Wildcard SAN *.example.com should be present in the certificate."
  }

  assert {
    condition     = length(aws_acm_certificate.this.subject_alternative_names) == 1
    error_message = "Expected exactly one SAN entry."
  }
}

run "skip_validation_wait_creates_no_validation_resource" {
  command = plan

  variables {
    domain_name         = "example.com"
    route53_zone_id     = "Z1234567890ABC"
    wait_for_validation = false
  }

  assert {
    condition     = length(aws_acm_certificate_validation.this) == 0
    error_message = "No aws_acm_certificate_validation resource should be created when wait_for_validation is false."
  }

  assert {
    condition     = length(aws_route53_record.validation) == 1
    error_message = "Exactly one deduplicated Route 53 validation record should be created even when wait_for_validation is false."
  }
}

run "tags_are_applied_to_certificate" {
  command = plan

  variables {
    domain_name     = "example.com"
    route53_zone_id = "Z1234567890ABC"
    tags = {
      environment = "production"
      team        = "platform"
    }
  }

  assert {
    condition     = aws_acm_certificate.this.tags["environment"] == "production"
    error_message = "environment tag should be set to production on the certificate."
  }

  assert {
    condition     = aws_acm_certificate.this.tags["team"] == "platform"
    error_message = "team tag should be set to platform on the certificate."
  }
}
