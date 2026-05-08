# aws/vpc

Creates a VPC with public subnets, an Internet Gateway, and a public route table. Designed for workloads that need direct internet access (e.g. self-hosted GitHub Actions runners) without the cost of a NAT gateway.

## Usage

```hcl
module "vpc" {
  source = "../../modules/aws/vpc"

  app_name               = "myapp"
  deployment_environment = "prod"
  vpc_cidr               = "10.0.0.0/16"
  public_subnet_cidrs    = ["10.0.1.0/24", "10.0.2.0/24"]
  availability_zones     = ["us-east-1a", "us-east-1b"]

  tags = {
    managed_by = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `app_name` | Application name. Used as a tag value on all resources. | `string` | — | yes |
| `deployment_environment` | Deployment environment (e.g. dev, staging, prod). Used as a tag value on all resources. | `string` | — | yes |
| `vpc_cidr` | CIDR block for the VPC. | `string` | `"10.0.0.0/16"` | no |
| `public_subnet_cidrs` | List of CIDR blocks for public subnets. One subnet is created per entry, in round-robin AZ order. | `list(string)` | `["10.0.1.0/24"]` | no |
| `availability_zones` | Explicit AZ names to assign subnets to. When empty, the module queries the current region. | `list(string)` | `[]` | no |
| `enable_dns_support` | Enable DNS resolution within the VPC. | `bool` | `true` | no |
| `enable_dns_hostnames` | Enable DNS hostnames for instances in the VPC. | `bool` | `true` | no |
| `tags` | Additional tags to apply to all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | ID of the created VPC. |
| `vpc_cidr` | CIDR block of the created VPC. |
| `public_subnet_ids` | List of public subnet IDs in the same order as `public_subnet_cidrs`. |
| `internet_gateway_id` | ID of the Internet Gateway attached to the VPC. |
| `public_route_table_id` | ID of the public route table. |

## Notes

- All public subnets have `map_public_ip_on_launch = true` so instances (e.g. self-hosted runners) can reach the internet without a NAT gateway.
- When `availability_zones` is empty the module uses an `aws_availability_zones` data source at plan time; pass explicit AZ names in contract tests or when deterministic placement is required.
- Only public subnets are created. Private subnets and NAT gateways are out of scope for this module.
