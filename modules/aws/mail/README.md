# aws/mail

Creates an SES domain-mail configuration with Route53 records for identity verification, DKIM, MAIL FROM, inbound MX, DMARC, and a configuration set.

## Inputs

| Name | Description | Type |
| --- | --- | --- |
| `deployment_environment` | Deployment environment name such as dev, staging, or prod. | `string` |
| `deployment_region` | Primary AWS region associated with this mail configuration. | `string` |
| `domain_name` | Fully qualified domain name for the SES identity. | `string` |
| `domain_prefix` | Subdomain label used for Route53 records within the hosted zone. | `string` |
| `route53_zone_id` | Route53 hosted zone ID for the DNS records. | `string` |
| `ses_inbound_region` | Optional inbound SMTP region override. | `string` |
| `ses_feedback_region` | Optional MAIL FROM feedback SMTP region override. | `string` |
| `tracking_redirect_domain` | Optional custom redirect domain for the SES configuration set. When omitted, no tracking redirect domain is configured. | `string` |
| `dmarc_policy` | Optional DMARC policy override. | `string` |
| `dmarc_report_uri` | Optional DMARC report URI override. | `string` |

## Outputs

| Name | Description |
| --- | --- |
| `configuration_set_name` | Name of the SES configuration set. |
| `identity_arn` | ARN of the SES domain identity. |
| `mail_from_domain` | MAIL FROM domain configured for SES. |

## Example

```hcl
module "mail" {
  source = "git::https://github.com/vln-devsecops/terraform-modules.git//modules/aws/mail?ref=v0.3"

  deployment_environment = "dev"
  deployment_region      = "us-east-1"
  domain_name            = "auth.example.com"
  domain_prefix          = "auth"
  route53_zone_id        = "Z1234567890"
}
```

The repository branch should remain `main`, while module consumers should normally prefer the moving two-level tag form such as `v0.3`.
