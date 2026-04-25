locals {
  effective_ses_inbound_region  = coalesce(var.ses_inbound_region, var.deployment_region)
  effective_ses_feedback_region = coalesce(var.ses_feedback_region, var.deployment_region)
  effective_dmarc_policy        = coalesce(var.dmarc_policy, "reject")
  effective_dmarc_report_uri    = coalesce(var.dmarc_report_uri, "mailto:dmarc-reports@${var.domain_name}")
  effective_tracking_domain     = coalesce(var.tracking_redirect_domain, var.domain_name)
}

resource "aws_ses_configuration_set" "this" {
  name = "ascs-${replace(var.domain_name, ".", "_")}-${var.deployment_environment}"

  delivery_options {
    tls_policy = "Require"
  }

  tracking_options {
    custom_redirect_domain = local.effective_tracking_domain
  }
}

resource "aws_ses_domain_identity" "identity" {
  domain = var.domain_name
}

resource "aws_route53_record" "identity_amazonses_verification_record" {
  zone_id = var.route53_zone_id
  name    = "_amazonses.${var.domain_name}"
  type    = "TXT"
  ttl     = 600
  records = [aws_ses_domain_identity.identity.verification_token]
}

resource "aws_ses_domain_identity_verification" "identity_verification" {
  domain = aws_ses_domain_identity.identity.domain

  depends_on = [aws_route53_record.identity_amazonses_verification_record]
}

resource "aws_ses_domain_dkim" "this" {
  domain = aws_ses_domain_identity.identity.domain

  depends_on = [aws_ses_domain_identity_verification.identity_verification]
}

resource "aws_route53_record" "dkim_record" {
  count   = 3
  zone_id = var.route53_zone_id
  name    = "${aws_ses_domain_dkim.this.dkim_tokens[count.index]}._domainkey.${var.domain_prefix}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_ses_domain_dkim.this.dkim_tokens[count.index]}.dkim.amazonses.com"]

  depends_on = [aws_ses_domain_identity_verification.identity_verification]
}

resource "aws_ses_domain_mail_from" "this" {
  domain           = aws_ses_domain_identity.identity.domain
  mail_from_domain = "bounce.${aws_ses_domain_identity.identity.domain}"
}

resource "aws_route53_record" "bounce_spf_record" {
  zone_id = var.route53_zone_id
  name    = "bounce.${var.domain_name}"
  type    = "TXT"
  ttl     = 300
  records = ["v=spf1 include:amazonses.com ~all"]
}

resource "aws_route53_record" "bounce_mx_record" {
  zone_id = var.route53_zone_id
  name    = "bounce.${var.domain_name}"
  type    = "MX"
  ttl     = 300
  records = ["10 feedback-smtp.${local.effective_ses_feedback_region}.amazonses.com"]
}

resource "aws_route53_record" "mx_record" {
  zone_id = var.route53_zone_id
  name    = var.domain_prefix
  type    = "MX"
  ttl     = 300
  records = ["1 inbound-smtp.${local.effective_ses_inbound_region}.amazonaws.com"]

  depends_on = [aws_ses_domain_identity_verification.identity_verification]
}

resource "aws_route53_record" "dmarc_record" {
  zone_id = var.route53_zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 300
  records = ["v=DMARC1; p=${local.effective_dmarc_policy}; rua=${local.effective_dmarc_report_uri}; aspf=r; adkim=r"]
}
