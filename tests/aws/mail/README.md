# Provider-backed mail suite

This suite exercises `modules/aws/mail` against real AWS APIs.

- fixture: `main.tf`
- entrypoint: `run.sh`
- prerequisites:
  - working AWS credentials in the environment
  - `MAIL_TEST_BASE_DOMAIN`, pointing at a real public Route53 parent zone such as `example.com`
  - `MAIL_TEST_ROUTE53_ZONE_ID`, the hosted zone ID for that parent zone

The suite creates a unique subdomain under the provided parent zone, verifies
the SES and Route53-facing outputs, and then destroys the fixture resources.
