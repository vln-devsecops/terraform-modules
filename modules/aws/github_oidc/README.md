# aws/github_oidc

Establishes GitHub Actions OIDC trust in an AWS account. Creates an IAM OIDC identity
provider for `token.actions.githubusercontent.com` and one or more IAM roles whose trust
policies allow GitHub Actions workflows to assume them via `sts:AssumeRoleWithWebIdentity`.

Only one OIDC provider per issuer can exist in an AWS account. If the provider already
exists (for example, because another Terraform root module created it), set
`create_oidc_provider = false` and the module will derive the provider ARN from the
current account identity instead.

## Inputs

| Name | Description | Type | Default |
| --- | --- | --- | --- |
| `create_oidc_provider` | Whether to create the OIDC provider. Set false if it already exists. | `bool` | `true` |
| `github_thumbprints` | Server certificate thumbprints for the GitHub OIDC endpoint. | `list(string)` | Current Starfield + DigiCert roots |
| `additional_audiences` | Extra audiences to register on the provider beyond `sts.amazonaws.com`. | `list(string)` | `[]` |
| `roles` | Map of IAM role definitions. See structure below. | `map(object)` | `{}` |
| `tags` | Tags applied to all created resources. | `map(string)` | `{}` |

### `roles` object structure

| Field | Description | Type | Default |
| --- | --- | --- | --- |
| `role_name` | IAM role name in AWS. | `string` | required |
| `description` | Human-readable description. | `string` | `""` |
| `subject_claims` | List of `token.actions.githubusercontent.com:sub` values to allow. Supports wildcards (`*`). | `list(string)` | required |
| `policy_arns` | Managed policy ARNs to attach to the role. | `list(string)` | `[]` |
| `inline_policies` | Map of inline policy name → JSON policy document. | `map(string)` | `{}` |
| `max_session_duration` | Maximum session duration in seconds. | `number` | `3600` |

**Subject claim examples:**

| Pattern | Grants access to |
| --- | --- |
| `repo:my-org/infra:environment:production` | Workflows running against the `production` GitHub environment |
| `repo:my-org/infra:ref:refs/heads/main` | Workflows triggered on the `main` branch |
| `repo:my-org/infra:pull_request` | Pull request workflows |
| `repo:my-org/infra:*` | Any workflow in the repo (least restrictive — prefer scoped claims) |

## Outputs

| Name | Description |
| --- | --- |
| `oidc_provider_arn` | ARN of the OIDC provider (created or derived). |
| `role_arns` | Map of role key → IAM role ARN for all created roles. |

## Examples

### Single account, two roles

```hcl
module "github_oidc" {
  source = "git::https://github.com/vln-devsecops/terraform-modules.git//modules/aws/github_oidc?ref=v0.5"

  tags = {
    org     = "my-org"
    managed = "terraform"
  }

  roles = {
    infra_plan = {
      role_name      = "my-org-infra-plan"
      description    = "Read-only plan role for infra PRs"
      subject_claims = ["repo:my-org/infra:pull_request"]
      policy_arns    = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    }

    infra_apply = {
      role_name      = "my-org-infra-apply"
      description    = "Write role for infra applies on main"
      subject_claims = ["repo:my-org/infra:environment:production"]
      inline_policies = {
        state_access = jsonencode({
          Version = "2012-10-17"
          Statement = [{
            Effect   = "Allow"
            Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
            Resource = ["arn:aws:s3:::my-state-bucket", "arn:aws:s3:::my-state-bucket/*"]
          }]
        })
      }
    }
  }
}

output "infra_apply_role_arn" {
  value = module.github_oidc.role_arns["infra_apply"]
}
```

### Sharing a provider across multiple modules

If the OIDC provider was already created by another module in the same root:

```hcl
module "github_oidc_extra_roles" {
  source = "git::https://github.com/vln-devsecops/terraform-modules.git//modules/aws/github_oidc?ref=v0.5"

  create_oidc_provider = false  # provider already exists in this account

  roles = {
    app_deploy = {
      role_name      = "my-org-app-deploy"
      subject_claims = ["repo:my-org/app:environment:staging"]
    }
  }
}
```

### Corresponding workflow step

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ vars.INFRA_APPLY_ROLE_ARN }}
      aws-region: ${{ vars.AWS_REGION }}
```

## Notes

- The module uses `StringLike` for subject claim conditions to support wildcard patterns.
  If all your claims are exact (no `*`), `StringLike` still works correctly for exact
  strings, so no special handling is needed.
- The audience is always pinned to `sts.amazonaws.com` using `StringEquals`. Additional
  audiences registered on the provider are available to the token issuer but are not
  automatically added to the trust condition.
- The `github_thumbprints` default covers both the Starfield (`6938fd4d...`) and
  DigiCert (`1c58a3a8...`) roots. AWS now validates GitHub OIDC tokens using the full
  certificate chain, so these thumbprints are not used for cryptographic verification,
  but the IAM API requires at least one entry.

The repository branch should remain `main`, while module consumers should normally prefer
the moving two-level tag form such as `v0.5`. That moving tag should only advance after
the relevant pipelines have passed on the target commit.
