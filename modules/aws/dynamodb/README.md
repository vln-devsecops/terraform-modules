# aws/dynamodb

Creates a DynamoDB table with optional secondary indexes and optional IAM user policy attachments.

## Inputs

| Name | Description | Type |
| --- | --- | --- |
| `app_name` | Name of the application owning the table. | `string` |
| `attributes` | Declared DynamoDB attributes used by the table and indexes. | `list(object({ name = string, type = string }))` |
| `deployment_environment` | Deployment environment name such as dev, staging, or prod. | `string` |
| `function` | Functional area served by the table. | `string` |
| `hash_key` | Partition key name. | `string` |
| `range_key` | Sort key name. | `string` |
| `global_secondary_indices` | Optional global secondary indexes. | `list(object(...))` |
| `local_secondary_indices` | Optional local secondary indexes. | `list(object(...))` |
| `rw_user_name` | Optional IAM user to attach a read-write policy to. | `string` |
| `ro_user_name` | Optional IAM user to attach a read-only policy to. | `string` |
| `short_deployment_region` | Short region identifier used in the table name. | `string` |

## Outputs

| Name | Description |
| --- | --- |
| `table_arn` | ARN of the DynamoDB table. |
| `table_name` | Name of the DynamoDB table. |

## Example

```hcl
module "dynamodb" {
  source = "git::https://github.com/vln-devsecops/terraform-modules.git//modules/aws/dynamodb?ref=v0.3"

  app_name               = "myapp"
  deployment_environment = "dev"
  short_deployment_region = "useast1"
  function               = "events"
  hash_key               = "pk"
  range_key              = "sk"

  attributes = [
    { name = "pk", type = "S" },
    { name = "sk", type = "S" },
  ]
}
```

The repository branch should remain `main`, while module consumers should normally prefer the moving two-level tag form such as `v0.3`.
