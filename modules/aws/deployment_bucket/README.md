# aws/deployment_bucket

Creates a versioned S3 bucket for deployment artifacts with public access blocked.

## Inputs

| Name | Description | Type |
| --- | --- | --- |
| `app_name` | Name of the application being deployed. | `string` |
| `deployment_environment` | Deployment environment name such as dev, staging, or prod. | `string` |
| `deployment_region` | Provider region identifier used in the bucket name. | `string` |

## Outputs

| Name | Description |
| --- | --- |
| `bucket_arn` | ARN of the deployment bucket. |
| `bucket_id` | ID of the deployment bucket. |
| `bucket_name` | Name of the deployment bucket. |

## Example

```hcl
module "deployment_bucket" {
  source = "git::https://github.com/vln-devsecops/terraform-modules.git//modules/aws/deployment_bucket?ref=v0.1"

  app_name               = "myapp"
  deployment_environment = "dev"
  deployment_region      = "us-east-1"
}
```

The repository branch should remain `main`, while module consumers should normally prefer the moving two-level tag form such as `v0.1`.
