# aws/lambda

Creates an AWS Lambda function backed by an S3 deployment archive, with a reusable execution role, KMS-backed environment and secret encryption, X-Ray tracing enabled by default, optional Function URL support, optional Secrets Manager support, optional extra S3 permissions, and optional extra IAM policy attachments.

The shared contract keeps the cleaner `coppice` shape while preserving the `docxchange` deployment archive naming convention by default. If `source_object_key` is omitted, the module looks for `${app_name}-${function_name}.zip`.

## Inputs

| Name | Description | Type |
| --- | --- | --- |
| `app_name` | Application name prefix. | `string` |
| `deployment_environment` | Deployment environment suffix. | `string` |
| `function_name` | Logical function name. | `string` |
| `handler_name` | Lambda handler name. | `string` |
| `runtime` | Lambda runtime. | `string` |
| `timeout` | Lambda timeout in seconds. | `number` |
| `memory_size` | Lambda memory size in MB. | `number` |
| `environment` | Lambda environment variables. | `map(string)` |
| `kms_key_arn` | Optional existing KMS key ARN to use for Lambda encryption. | `string` |
| `kms_key_policy_json` | Optional explicit KMS key policy JSON for the module-managed key. | `string` |
| `source_bucket_arn` | ARN of deployment source bucket. | `string` |
| `source_bucket_id` | Name or ID of deployment source bucket. | `string` |
| `source_object_key` | Optional S3 object key for the deployment archive. Defaults to `app_name-function_name.zip`. | `string` |
| `publish` | Whether to publish a new function version on update. | `bool` |
| `tracing_mode` | AWS X-Ray tracing mode for the Lambda function. | `string` |
| `create_url` | Whether to create a Lambda Function URL. | `bool` |
| `url_authorization_type` | Auth type for Lambda Function URL when create_url is true. | `string` |
| `create_secret` | Whether to create a Secrets Manager secret for the Lambda. | `bool` |
| `backend_user_name` | Optional IAM user that should be able to manage the generated secret. | `string` |
| `s3_required_access` | Optional extra S3 permissions keyed by a stable identifier. | `map(object({ action = string, resources = list(string) }))` |
| `additional_role_policy_arns` | Optional existing IAM policy ARNs to attach to the Lambda execution role. | `list(string)` |
| `assume_role_services` | AWS services allowed to assume the execution role. | `list(string)` |

## Outputs

| Name | Description |
| --- | --- |
| `arn` | ARN of the Lambda function. |
| `function_name` | Name of the Lambda function. |
| `qualified_arn` | Qualified ARN of the Lambda function. |
| `role_arn` | ARN of the Lambda execution role. |
| `role_name` | Name of the Lambda execution role. |
| `kms_key_arn` | ARN of the KMS key used for Lambda environment and secret encryption. |
| `url` | Function URL when create_url is true. |
| `secret_arn` | ARN of the generated secret when create_secret is true. |
| `secret_name` | Name of the generated secret when create_secret is true. |

## Example

```hcl
module "lambda" {
  source = "git::https://github.com/vln-devsecops/terraform-modules.git//modules/aws/lambda?ref=v0.4"

  app_name               = "sampleapp"
  deployment_environment = "dev"
  function_name          = "api"

  source_bucket_arn = "arn:aws:s3:::deployment-sampleapp"
  source_bucket_id  = "deployment-sampleapp"
  source_object_key = "lambdas/api/release.zip"

  create_url             = true
  url_authorization_type = "AWS_IAM"
  timeout                = 30
  memory_size            = 256

  environment = {
    APP_ENV = "dev"
  }
}
```

The repository branch should remain `main`, while module consumers should normally prefer the moving two-level tag form such as `v0.4`. That moving tag should only advance after the relevant pipelines have passed on the target commit.
