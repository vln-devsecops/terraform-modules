# aws/static_site example

Minimal example showing how to create an AWS-backed static site hostname with
the shared `aws/static_site` module.

This example expects:

- an existing Route53 public hosted zone
- an existing ACM certificate ARN in `us-east-1` for the site hostname

Use the provider-backed suite under `tests/aws/static_site` when you want the
repository to create and validate the certificate automatically for a temporary
test hostname.
