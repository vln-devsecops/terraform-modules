output "configuration_set_name" {
  description = "Name of the SES configuration set."
  value       = aws_ses_configuration_set.this.name
}

output "identity_arn" {
  description = "ARN of the SES domain identity."
  value       = aws_ses_domain_identity.identity.arn
}

output "mail_from_domain" {
  description = "MAIL FROM domain configured for SES."
  value       = aws_ses_domain_mail_from.this.mail_from_domain
}
