resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alt_names
  validation_method         = var.validation_method

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

locals {
  # Deduplicate apex/wildcard validation records while keeping stable, plan-time keys.
  validation_domains_grouped = {
    for domain in concat([var.domain_name], var.subject_alt_names) :
    (contains(var.subject_alt_names, "*.${trimprefix(domain, "*.")}") ? "*.${trimprefix(domain, "*.")}" : trimprefix(domain, "*.")) => trimprefix(domain, "*.")...
  }

  validation_domains_by_key = {
    for key, values in local.validation_domains_grouped : key => values[0]
  }
}

resource "aws_route53_record" "validation" {
  for_each = local.validation_domains_by_key

  zone_id = var.route53_zone_id
  name = element([
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.resource_record_name
    if trimprefix(dvo.domain_name, "*.") == each.value
  ], 0)
  type = element([
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.resource_record_type
    if trimprefix(dvo.domain_name, "*.") == each.value
  ], 0)
  ttl = 60
  records = [element([
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.resource_record_value
    if trimprefix(dvo.domain_name, "*.") == each.value
  ], 0)]
}

resource "aws_acm_certificate_validation" "this" {
  count = var.wait_for_validation ? 1 : 0

  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}
