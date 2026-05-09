# aws/s3_replication

Enables S3 replication from a source bucket to a central (cross-account) log aggregation bucket.

Enables versioning on the source bucket (required by S3 for replication), creates an IAM replication role, and configures an S3 replication rule.

## Usage

```hcl
module "cloudfront_log_replication" {
  source = "git::https://github.com/vln-devsecops/terraform-modules.git//modules/aws/s3_replication?ref=vX.Y"

  source_bucket_id       = aws_s3_bucket.cloudfront_logs.id
  source_bucket_arn      = aws_s3_bucket.cloudfront_logs.arn
  destination_bucket_arn = var.central_logs_bucket_arn
  role_name              = "my-app-cloudfront-log-replication"
  rule_id                = "replicate-my-app-cloudfront-to-devsecops"
  tags                   = local.common_tags
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `source_bucket_id` | ID (name) of the source S3 bucket | `string` | - | yes |
| `source_bucket_arn` | ARN of the source S3 bucket | `string` | - | yes |
| `destination_bucket_arn` | ARN of the central logs destination bucket | `string` | - | yes |
| `role_name` | IAM role name for the replication role | `string` | - | yes |
| `rule_id` | Replication rule identifier | `string` | `"replicate-to-central-logs"` | no |
| `destination_storage_class` | Storage class in the destination bucket | `string` | `"STANDARD"` | no |
| `tags` | Tags to apply to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `replication_role_arn` | ARN of the IAM replication role |
| `replication_role_name` | Name of the IAM replication role |
