# aws/acm_certificate

Provisions an ACM certificate with DNS validation, the required Route 53 CNAME records, and (optionally) waits for validation to complete.

Designed to be used with a provider alias so CloudFront certificates can be issued in `us-east-1` regardless of where the rest of your stack lives.

## Usage

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "certificate" {
  source = "../../modules/aws/acm_certificate"

  domain_name       = "example.com"
  subject_alt_names = ["*.example.com"]
  route53_zone_id   = aws_route53_zone.primary.zone_id

  tags = {
    managed_by = "terraform"
  }

  providers = {
    aws = aws.us_east_1
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `domain_name` | Primary domain name for the certificate. | `string` | — | yes |
| `subject_alt_names` | Subject alternative names to include in the certificate. | `list(string)` | `[]` | no |
| `route53_zone_id` | Route 53 hosted zone ID used for DNS validation records. | `string` | — | yes |
| `validation_method` | Certificate validation method. Only `"DNS"` is supported. | `string` | `"DNS"` | no |
| `wait_for_validation` | Whether to wait for certificate validation to complete before returning. | `bool` | `true` | no |
| `tags` | Additional tags to apply to the certificate. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `certificate_arn` | ARN of the validated ACM certificate. |
| `certificate_domain_name` | Primary domain name of the certificate. |
| `validation_record_fqdns` | FQDNs of the DNS validation records created in Route 53. |

## Notes

- Only DNS validation is supported; the module enforces this via an input validation rule.
- Pass `wait_for_validation = false` to skip the `aws_acm_certificate_validation` resource (useful when the Route 53 zone is managed outside Terraform or when you want to orchestrate validation separately).
- The module does not hard-code a provider, so the caller controls which region the certificate is issued in via provider aliasing.
