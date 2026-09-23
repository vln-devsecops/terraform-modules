# SES identity for the auth API's own signup/password-reset emails.
#
# The vlinder_auth module hard-requires `ses_configuration` whenever it
# provisions the public auth API ("full" or "auth_api" profiles, the default
# being "full") -- auth_api generates and emails its own verification/reset
# codes via SES, with no zero-config fallback the way COGNITO_DEFAULT was for
# Cognito's own built-in email (see the module's
# check.ses_configuration_required_for_public_auth_api). This suite never
# provided one at all, so it has never actually gotten past `terraform plan`'s
# precondition check -- confirmed via a real failed `terraform apply` in CI,
# the same way infra/demo/vlinder_auth/ses.tf's identical setup was first
# motivated (see that file for the fuller writeup this comment intentionally
# doesn't repeat).
#
# Unlike that demo (a long-lived root, fixed subdomain, re-verification
# would be wasted churn), this suite applies then destroys on every single
# run (see run.sh), so the domain is keyed off name_suffix like the ACM
# certificate above it -- a fixed subdomain here would risk two concurrent
# runs (e.g. a workflow_dispatch overlapping the weekly schedule, or two
# different branches) racing to verify/destroy the same SES identity.

locals {
  ses_domain = "mail-${var.name_suffix}.${var.base_domain}"
}

resource "aws_ses_domain_identity" "test" {
  domain = local.ses_domain
}

resource "aws_route53_record" "ses_verification" {
  zone_id = var.route53_zone_id
  name    = "_amazonses.${aws_ses_domain_identity.test.domain}"
  type    = "TXT"
  records = [aws_ses_domain_identity.test.verification_token]
  ttl     = 60
}

# Blocks until SES actually considers the domain verified (polls DNS), same
# role aws_acm_certificate_validation plays for the ACM cert above -- without
# it, `terraform apply` could return before verification completes, and the
# ses_configuration wired into the module would point at an identity that
# isn't actually usable yet.
resource "aws_ses_domain_identity_verification" "test" {
  domain = aws_ses_domain_identity.test.id

  depends_on = [aws_route53_record.ses_verification]
}

resource "aws_sesv2_configuration_set" "test" {
  configuration_set_name = "vlinder-auth-test-${var.name_suffix}"

  delivery_options {
    tls_policy = "REQUIRE"
  }
}
