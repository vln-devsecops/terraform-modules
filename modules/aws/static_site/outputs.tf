output "site_name" {
  description = "Fully qualified site hostname."
  value       = var.site_name
}

output "site_url" {
  description = "Primary HTTPS URL for the site."
  value       = "https://${var.site_name}"
}

output "bucket_name" {
  description = "S3 bucket name serving static site content."
  value       = aws_s3_bucket.site.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket serving static site content."
  value       = aws_s3_bucket.site.arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID for invalidation and operations."
  value       = aws_cloudfront_distribution.site.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN."
  value       = aws_cloudfront_distribution.site.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "route53_record_name" {
  description = "Route53 alias record name."
  value       = aws_route53_record.site_a.name
}
