# terraform-modules

Reusable Terraform modules for shared infrastructure patterns.

The repository branch is `main`. Modules should be consumed via version tags rather than by floating branch references.

Documentation should normally use the moving two-level tag form such as `v0.3`; patch tags such as `v0.3.0` remain the immutable release points.

Version tags should only be created or moved after the relevant pipelines have been confirmed to pass on the tagged commit.

## Layout

- `modules/aws/*`: AWS-specific shared modules
- `examples/aws/*`: runnable example configurations for AWS modules
- `tests/aws/*`: reserved for higher-level integration suites

## Current modules

| Module | Description |
| --- | --- |
| `modules/aws/acm_certificate` | ACM certificate with Route 53 DNS validation, wildcard SANs, and provider-aliased `us-east-1` support |
| `modules/aws/central_logs` | S3-based central log aggregation for multi-account organisations, with KMS encryption, Glacier lifecycle, cross-account write policy, and optional multi-region CloudTrail |
| `modules/aws/deployment_bucket` | S3 bucket for Lambda deployment archives, with KMS encryption and versioning |
| `modules/aws/dynamodb` | DynamoDB table with optional KMS encryption, TTL, and IAM access policies |
| `modules/aws/github_oidc` | GitHub Actions OIDC identity provider and IAM roles for keyless AWS access |
| `modules/aws/http_api` | API Gateway HTTP API (v2) with Lambda integrations, JWT authorizers (e.g. Coppice), and optional custom domain |
| `modules/aws/lambda` | Lambda function backed by an S3 archive, with KMS, X-Ray, optional URL and Secrets Manager |
| `modules/aws/lambda-at-edge` | Lambda@Edge variant with CloudFront replication trust and IAM |
| `modules/aws/mail` | SES domain identity, DKIM, Route 53 records, and sending IAM policy |
| `modules/aws/s3_replication` | S3 cross-bucket replication with IAM role, versioning, and configurable storage class |
| `modules/aws/static_site` | CloudFront + S3 static site with ACM, Route 53, SPA fallback, WAF, access logging, and response headers policy |
| `modules/aws/vpc` | VPC with public subnets and Internet Gateway (no NAT gateway) |

## Testing approach

Shared modules use a layered test model:

1. static checks on every change with `terraform fmt -check`, `terraform validate`, `tflint`, and `trivy config`
2. module contract tests with `terraform test`
3. executable examples under `examples/`
4. scheduled/manual compliance checks with `checkov`, keeping clearly consumer-specific controls explicitly allowlisted until the shared modules grow first-class support for them
5. provider-backed integration suites under `tests/aws/*/run.sh`
6. higher-level cloud integration coverage that can be executed locally with AWS credentials or from GitHub Actions once the required secrets and variables are configured

The repository CI also enforces that every discovered module has both contract tests with real assertions and a matching example directory, so a green workflow means the module tree was actually discovered and exercised.

For local AWS test-user setup, `tests/aws/aws-live-suite-test-user-policy.json`
contains a single custom IAM policy that covers the provider-backed suites. Update
the Route53 hosted zone placeholder before attaching it if you want to run the
mail suite, and refresh that value whenever `MAIL_TEST_ROUTE53_ZONE_ID` changes.

At the moment, `deployment_bucket` and `dynamodb` have static checks, contract tests, and executable examples in place. Their higher-level AWS integration coverage is still deferred.

`lambda` now adds both mock-provider contract coverage and a provider-backed compatibility fixture under `tests/aws/lambda/doxchange_compat` so the closest-to-production `doxchange` usage shape stays protected while the shared module evolves.
