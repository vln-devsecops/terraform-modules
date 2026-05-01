# aws/static_site live suite

Provider-backed coverage for `modules/aws/static_site`.

The suite:

- creates a temporary hostname under a delegated public base domain
- requests and validates an ACM certificate in `us-east-1`
- applies the shared `aws/static_site` module
- verifies the S3 bucket, CloudFront distribution, and Route53 alias records

## Environment

Set one of these variable pairs before running:

- `STATIC_SITE_TEST_BASE_DOMAIN` and `STATIC_SITE_TEST_ROUTE53_ZONE_ID`
- or reuse `MAIL_TEST_BASE_DOMAIN` and `MAIL_TEST_ROUTE53_ZONE_ID`

The second form is convenient when the shared delegated mail-test domain is the
only public delegated zone currently available in the `vln-devsecops` AWS
account.
