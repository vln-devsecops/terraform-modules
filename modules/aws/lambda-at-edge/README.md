# aws/lambda-at-edge

Thin wrapper around `aws/lambda` for functions deployed as Lambda@Edge (CloudFront origin-request or origin-response handlers).

The wrapper hardens two Lambda@Edge requirements that callers would otherwise have to remember:

- `publish = true` is hardcoded — Lambda@Edge functions must be versioned.
- Both `lambda.amazonaws.com` and `edgelambda.amazonaws.com` are always included in the execution role trust policy.

In addition the module creates the standard replication IAM policy and attaches it to the execution role, so CloudFront can replicate the function to edge locations. This is the app-local boilerplate that consumers would otherwise need to manage themselves.

**The source bucket must be in `us-east-1`.** This is an AWS requirement for Lambda@Edge functions.

## Inputs

All inputs from `aws/lambda` are supported **except** `publish` and `assume_role_services`, which are hardcoded.

| Name | Description | Type | Default |
| --- | --- | --- | --- |
| `app_name` | Application name prefix. | `string` | required |
| `deployment_environment` | Deployment environment suffix. | `string` | required |
| `function_name` | Logical function name. | `string` | required |
| `source_bucket_arn` | ARN of the deployment source bucket (must be us-east-1). | `string` | required |
| `source_bucket_id` | Name or ID of the deployment source bucket. | `string` | required |
| `handler_name` | Lambda handler name. | `string` | `"index.handler"` |
| `runtime` | Lambda runtime. | `string` | `"nodejs22.x"` |
| `timeout` | Lambda timeout in seconds. | `number` | `3` |
| `memory_size` | Lambda memory size in MB. | `number` | `128` |
| `environment` | Lambda environment variables. | `map(string)` | `{}` |
| `kms_key_arn` | Optional existing KMS key ARN. | `string` | `null` |
| `kms_key_policy_json` | Optional explicit KMS key policy JSON. | `string` | `null` |
| `source_object_key` | Optional S3 object key. Defaults to `app_name-function_name.zip`. | `string` | `null` |
| `tracing_mode` | AWS X-Ray tracing mode. | `string` | `"Active"` |
| `create_url` | Whether to create a Lambda Function URL. | `bool` | `false` |
| `url_authorization_type` | Auth type for Function URL. | `string` | `"NONE"` |
| `create_secret` | Whether to create a Secrets Manager secret. | `bool` | `false` |
| `backend_user_name` | Optional IAM user for secret management. | `string` | `null` |
| `s3_required_access` | Optional extra S3 permissions. | `map(object)` | `{}` |
| `additional_role_policy_arns` | Optional extra IAM policy ARNs to attach. | `list(string)` | `[]` |

## Outputs

| Name | Description |
| --- | --- |
| `arn` | ARN of the Lambda function. |
| `function_name` | Name of the Lambda function. |
| `qualified_arn` | Qualified ARN of the Lambda function. |
| `role_arn` | ARN of the Lambda execution role. |
| `role_name` | Name of the Lambda execution role. |
| `kms_key_arn` | ARN of the KMS key used for encryption. |
| `url` | Function URL when `create_url` is true. |
| `secret_arn` | ARN of the generated secret when `create_secret` is true. |
| `secret_name` | Name of the generated secret when `create_secret` is true. |
| `edge_replication_policy_arn` | ARN of the Lambda@Edge replication IAM policy. |

## Example

```hcl
module "origin_response" {
  source = "git::https://github.com/vln-devsecops/terraform-modules.git//modules/aws/lambda-at-edge?ref=v0.5"

  app_name               = "myapp"
  deployment_environment = "prod"
  function_name          = "origin-response"

  # Must be in us-east-1
  source_bucket_arn = module.deployment_buckets["us-east-1"].bucket_arn
  source_bucket_id  = module.deployment_buckets["us-east-1"].bucket_id

  s3_required_access = {
    read_frontend = {
      action    = "s3:GetObject"
      resources = ["${aws_s3_bucket.frontend.arn}/*"]
    }
    list_frontend = {
      action    = "s3:ListBucket"
      resources = [aws_s3_bucket.frontend.arn]
    }
  }
}
```

The module ref should use the moving two-level tag form (`v0.5`) rather than a branch. That tag advances only after CI passes on the target commit.
