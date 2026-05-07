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

## Prerequisites

### AWS side

**First apply — bootstrap credentials**

There is a chicken-and-egg problem: you need AWS credentials to create the OIDC
provider and roles, but those roles are what you want instead of long-lived credentials.

For the initial setup, run `terraform apply` locally (or in CI) using an existing IAM
user or admin credentials. Once the roles exist, update your workflows to use OIDC and
then you can stop using the static credentials.

**Minimum IAM permissions for the applying identity**

The identity running `terraform apply` needs at least:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "OIDCProvider",
      "Effect": "Allow",
      "Action": [
        "iam:CreateOpenIDConnectProvider",
        "iam:GetOpenIDConnectProvider",
        "iam:UpdateOpenIDConnectProviderThumbprint",
        "iam:AddClientIDToOpenIDConnectProvider",
        "iam:DeleteOpenIDConnectProvider",
        "iam:TagOpenIDConnectProvider",
        "iam:ListOpenIDConnectProviderTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMRoles",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:GetRole",
        "iam:UpdateAssumeRolePolicy",
        "iam:DeleteRole",
        "iam:TagRole",
        "iam:ListRoleTags",
        "iam:PutRolePolicy",
        "iam:GetRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:ListRolePolicies",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies"
      ],
      "Resource": "arn:aws:iam::*:role/YOUR-ROLE-PREFIX-*"
    }
  ]
}
```

Scope the `Resource` in `IAMRoles` to match your role naming convention. If your roles
are not prefixed, use `"arn:aws:iam::*:role/*"` but prefer a prefix for least privilege.

### GitHub side

**`permissions: id-token: write` is required**

GitHub does not mint an OIDC token for a workflow job unless the job (or the calling
workflow) explicitly requests it:

```yaml
permissions:
  id-token: write   # required — GitHub will not issue an OIDC token without this
  contents: read
```

If this is omitted the `aws-actions/configure-aws-credentials` step will fail with an
error like `Credentials could not be loaded` or a 401 from the OIDC token endpoint.

**Org-level OIDC token issuance**

Some GitHub organisations disable OIDC token issuance for Actions by policy. If your
workflows fail with an error about OIDC tokens being disabled, an organisation owner
needs to allow it under **Settings → Actions → General → Allow GitHub Actions to
request OIDC tokens**.

**Subject claim customisation (recommended for production)**

By default GitHub's `sub` claim format depends on the workflow context:

| Workflow context | Default `sub` value |
| --- | --- |
| Job targeting a GitHub environment | `repo:OWNER/REPO:environment:ENV` |
| Job on a branch (no environment) | `repo:OWNER/REPO:ref:refs/heads/BRANCH` |
| Pull request | `repo:OWNER/REPO:pull_request` |

This means a job running *without* an environment can potentially match a
`repo:OWNER/REPO:*` subject claim and assume a role that was intended only for
environment-gated workflows.

To harden this, set the org-level OIDC subject customisation so that the `sub` claim
always includes the environment field. Run this once per GitHub organisation (requires
org owner permissions):

```bash
gh api \
  --method PUT \
  /orgs/YOUR-ORG/actions/oidc/customization/sub \
  --field 'include_claim_keys[]=repo' \
  --field 'include_claim_keys[]=environment'
```

After this change, jobs that do not target a named GitHub environment will have
`environment` set to an empty string in the `sub` claim, making
`repo:OWNER/REPO:environment:production` unmatchable from a branch-only job.

Individual repositories can override the org setting under **Settings → Code and
automation → Actions → General → OIDC token customisation**. Avoid per-repo overrides
unless you have a specific reason — consistent org-wide behaviour is easier to audit.

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
