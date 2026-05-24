# aws/static_site

Creates an AWS-backed static site with a private S3 origin, CloudFront OAC,
Route53 alias records, SPA-friendly rewrites, and optional lightweight
basic-auth at the viewer-request edge.

By default, the module seeds placeholder `default_root_object` and
`404.html` objects so the site is reachable for smoke testing before the real
frontend content is deployed. After deploying real frontend content, set
`create_placeholder_site = false` to avoid Terraform restoring placeholders on
future applies.
## Inputs

| Name | Description | Type |
| --- | --- | --- |
| `site_name` | Fully qualified hostname for the static site. | `string` |
| `route53_zone_id` | Route53 hosted zone ID that serves the site hostname. | `string` |
| `acm_certificate_arn` | ACM certificate ARN in `us-east-1` for the CloudFront alias domain. | `string` |
| `default_root_object` | Default root object served by CloudFront. | `string` |
| `cloudfront_price_class` | CloudFront price class for the site distribution. | `string` |
| `http_version` | CloudFront HTTP version. | `string` |
| `force_destroy` | Whether to allow the site bucket to be force-destroyed. | `bool` |
| `enable_spa_fallback` | Whether to rewrite 403 and 404 responses to `index.html`. | `bool` |
| `enable_pretty_urls` | Whether to rewrite extensionless viewer requests to `index.html` paths. | `bool` |
| `basic_auth_enabled` | Whether to require HTTP basic auth at the CloudFront viewer-request edge. | `bool` |
| `basic_auth_username` | Basic-auth username when `basic_auth_enabled` is true. | `string` |
| `basic_auth_password` | Basic-auth password when `basic_auth_enabled` is true. | `string` |
| `basic_auth_realm` | Realm label returned in the `WWW-Authenticate` challenge. | `string` |
| `tags` | Additional tags to apply to created resources. | `map(string)` |
| `create_placeholder_site` | Whether to seed placeholder `index.html` and `404.html` content objects. | `bool` |
| `placeholder_index_html` | Optional custom HTML content used only for initial placeholder seeding; later content changes are ignored so site deployment workflows can manage object contents. | `string` |
| `placeholder_404_html` | Optional custom HTML content used only for initial placeholder seeding; later content changes are ignored so site deployment workflows can manage object contents. | `string` |

## Outputs

| Name | Description |
| --- | --- |
| `site_name` | Fully qualified site hostname. |
| `site_url` | Primary HTTPS URL for the site. |
| `bucket_name` | S3 bucket name serving static site content. |
| `bucket_arn` | ARN of the S3 bucket serving static site content. |
| `cloudfront_distribution_id` | CloudFront distribution ID for invalidation and operations. |
| `cloudfront_distribution_arn` | CloudFront distribution ARN. |
| `cloudfront_domain_name` | CloudFront distribution domain name. |
| `route53_record_name` | Route53 alias record name. |

## Example

```hcl
module "static_site" {
  source = "git::https://github.com/vln-devsecops/terraform-modules.git//modules/aws/static_site?ref=v0.4"

  site_name           = "dashboard-4f8k2m1q9z.devsecops.vlinder.ca"
  route53_zone_id     = "Z1234567890"
  acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/example"
}
```

For low-sensitivity internal dashboards, the recommended default is to keep
`basic_auth_enabled = false` and rely first on an unguessable hostname. If you
later enable basic auth, remember that those credentials will be rendered into
the CloudFront function code and therefore remain part of the deployed
configuration and Terraform state.
