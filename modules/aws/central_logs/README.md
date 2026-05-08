# aws/central_logs

Provisions a cost-optimised, S3-based central log aggregation bucket for a multi-account AWS organisation. Designed for a batch-processing pattern where logs accumulate in S3 and a scheduled job (e.g. daily) parses them offline — no live alerting, no Kinesis.

Child accounts (e.g. vln-bookstore) deliver CloudFront and CloudTrail logs into the central bucket using cross-account S3 writes. An optional multi-region CloudTrail trail can be created in the central account and deliver directly to the same bucket.

## Usage

```hcl
module "central_logs" {
  source = "../../modules/aws/central_logs"

  bucket_name = "acme-org-central-logs"

  allowed_account_ids = [
    "111111111111", # vln-bookstore
    "222222222222", # vln-platform
  ]

  enable_cloudtrail = true
  cloudtrail_name   = "org-central-trail"

  tags = {
    managed_by  = "terraform"
    environment = "production"
  }
}

output "log_bucket_arn" {
  value = module.central_logs.bucket_arn
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `bucket_name` | S3 bucket name for central logs. | `string` | — | yes |
| `allowed_account_ids` | AWS account IDs allowed to write logs into the bucket via cross-account PutObject. | `list(string)` | — | yes |
| `create_kms_key` | Whether to create a KMS key for bucket encryption. When false, SSE-S3 (AES256) is used. | `bool` | `true` | no |
| `kms_key_deletion_window_days` | Waiting period in days before KMS key deletion (7–30). | `number` | `30` | no |
| `standard_retention_days` | Days to keep objects in S3 Standard before transitioning to Glacier Instant Retrieval. | `number` | `90` | no |
| `glacier_retention_years` | Years to retain objects in Glacier Instant Retrieval before expiry. Total lifecycle = `standard_retention_days + glacier_retention_years * 365`. | `number` | `7` | no |
| `enable_cloudtrail` | Whether to create a multi-region CloudTrail trail delivering to this bucket. | `bool` | `false` | no |
| `cloudtrail_name` | Name for the CloudTrail trail. Only used when `enable_cloudtrail = true`. | `string` | `"central-logs-trail"` | no |
| `tags` | Additional tags to apply to all taggable resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_name` | Name of the central logs S3 bucket. |
| `bucket_arn` | ARN of the central logs S3 bucket. |
| `kms_key_arn` | ARN of the KMS key used for bucket encryption, or `null` when `create_kms_key` is false. |
| `kms_key_id` | Key ID of the KMS key, or `null` when `create_kms_key` is false. |
| `cloudtrail_arn` | ARN of the CloudTrail trail, or `null` when `enable_cloudtrail` is false. |

## Notes

- **Cross-account write access**: Child accounts must set the `x-amz-acl: bucket-owner-full-control` header on every `PutObject` call so the central account owns the objects. Without this header the `AllowCrossAccountPutObject` bucket policy statement will deny the request.

- **CloudFront access logs**: CloudFront's native access log delivery does not support the `x-amz-acl` header, so it cannot write directly to a bucket in a different account. The recommended pattern is to have each child account receive CloudFront logs into a local S3 bucket and then configure S3 replication (with ownership override) from that local bucket into this central bucket.

- **Batch processing pattern**: Logs accumulate in S3 Standard for `standard_retention_days` (default 90 days), then transition to Glacier Instant Retrieval for cost savings during the remainder of the 7-year retention window, and are automatically expired after `standard_retention_days + glacier_retention_years * 365` days. A scheduled job (e.g. an AWS Glue crawler or a daily Lambda) can query the data in place using Athena without needing to restore from Glacier, since Glacier Instant Retrieval supports millisecond access.

- **CloudTrail delivery**: When `enable_cloudtrail = true`, the bucket policy gains an extra statement permitting `cloudtrail.amazonaws.com` to write objects under the `cloudtrail/AWSLogs/` prefix. The `depends_on` on the trail resource ensures the policy is in place before CloudTrail tries to validate delivery.
