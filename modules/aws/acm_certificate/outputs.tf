output "certificate_arn" {
  description = "ARN of the validated ACM certificate."
  value       = aws_acm_certificate.this.arn
}

output "certificate_domain_name" {
  description = "Primary domain name of the certificate."
  value       = aws_acm_certificate.this.domain_name
}

output "validation_record_fqdns" {
  description = "FQDNs of the DNS validation records created in Route 53."
  value       = [for record in aws_route53_record.validation : record.fqdn]
}
