# aws/cognito_auth

A self-provisioning Cognito auth component: a consumer supplies an app id and
the unavoidable AWS plumbing (an existing Route 53 zone and a us-east-1 ACM
certificate — no module in this repo can conjure those) and gets back a
working Cognito-backed signup/login flow, RBAC, and a hosted admin panel. No
Lambda ARNs, no DynamoDB tables, and no second API to wire by hand.

```hcl
module "auth" {
  source = "git::https://github.com/vln-devsecops/terraform-modules.git//modules/aws/cognito_auth?ref=v0.1"

  app_name                = "myapp"
  deployment_environment  = "prod"
  route53_zone_id         = "Z1234567890"
  acm_certificate_arn     = "arn:aws:acm:us-east-1:123456789012:certificate/example"

  # everything below is optional, sanely defaulted
  logo_base64 = filebase64("logo.png")
  css         = ".label-customizable { font-weight: 400; }"
}
```

The `acm_certificate_arn` must cover both hostnames this module derives
(`auth-<zone>` for the hosted UI, `admin-<zone>` for the bundled admin panel)
— a wildcard cert from [`aws/acm_certificate`](../acm_certificate) is the
simplest way to get that.

## Why this diverges from this repo's usual module style

Most modules in this repo are thin, bring-your-own-compute wrappers (see
`static_site`'s `origin_response_lambda_qualified_arn`). `cognito_auth` is
different on purpose: it provisions its own Lambda functions, DynamoDB
tables, HTTP API, and static site internally rather than asking the consumer
to build and wire them. Internally it still composes the existing
[`aws/lambda`](../lambda)-adjacent patterns, [`aws/dynamodb`](../dynamodb),
[`aws/http_api`](../http_api), and [`aws/static_site`](../static_site) — DRY
on the inside, minimal-input on the outside.

One real exception: the three Lambda functions are **not** built via
`aws/lambda`, because that module expects a pre-built artifact already
uploaded to an S3 deployment bucket (falling back to a placeholder "echo"
function otherwise) — a convention built for app code deployed independently
of infra changes. This module's Lambda source is vendored/committed inside
the module itself (`lambda-src/`, currently bootstrap placeholders — see
[`lambda-src/README.md`](lambda-src/README.md)) and zipped directly via
`archive_file`, so it's self-contained on the very first `terraform apply`.

## RBAC and tenancy

Role is kept separate from privileges. `roles` is a Terraform-seeded catalog
— not runtime-editable, which is what keeps the bundled admin API light —
mapping a role name to the privileges it grants and whether it's tenant-scoped
or global:

```hcl
roles = {
  member = {
    privileges   = []
    tenant_scope = "tenant"
  }
  tenant-admin = {
    privileges   = ["admin:users:read:own", "admin:users:write:own", "admin:roles:read"]
    tenant_scope = "tenant"
  }
  super-admin = {
    privileges   = ["admin:users:read:*", "admin:users:write:*", "admin:roles:read"]
    tenant_scope = "global"
  }
}
```

Only the resolved **privileges** — never the role name — land in the issued
JWT (as a `permissions` claim, alongside `tenantId`). A role's `tenant_scope`
of `"global"` is what makes it a super-admin-style role (cross-tenant); both
scopes are the same mechanism.

`tenancy_mode` defaults to `"single"`: exactly one implicit tenant, no
tenant table exposed for CRUD, no tenant switcher in the admin panel. Set it
to `"multi"` and populate `tenants` (keyed by tenantId, with an
`email_domain` driving the post-confirmation trigger's tenant-resolution
lookup) for real multi-tenant behavior.

## The bundled admin panel

On by default (`create_admin_panel = true`). Hosted at
`admin-<zone>` via `aws/static_site`, with its own Cognito app client
(no self-signup client-side — Cognito's `admin_create_user_config` is
pool-wide, so the real security boundary is the admin API's own privilege
checks, not which client a caller authenticated through) and its own
`aws/http_api` behind a JWT authorizer pointed at this module's own pool.
Tenant-scoped callers (`:own` privileges) see only their own tenant's users;
global-scoped callers (`:*` privileges) see across all tenants.

The panel's *built* static assets are **not** vendored into this module —
`static_site`'s bucket/CloudFront naming is only known after apply, so
uploading real content is a deploy-pipeline concern, same as any other
`static_site` consumer. Use the `admin_api_invoke_url` and
`admin_panel_client_id` outputs to inject runtime config (a `config.json`
fetched at load time — Vite env vars are baked in at build time and can't
know these values yet).

## Inputs

| Name | Description | Type |
| --- | --- | --- |
| `app_name` | Application name prefix. | `string` |
| `deployment_environment` | Deployment environment suffix. | `string` |
| `route53_zone_id` | Route53 hosted zone ID serving the derived hostnames. | `string` |
| `acm_certificate_arn` | ACM certificate ARN in `us-east-1` covering both derived hostnames. | `string` |
| `logo_base64` | Base64-encoded hosted-UI logo. Omitted (no custom logo) when null. | `string` |
| `css` | Hosted-UI CSS override. Defaults to a built-in Vlinder theme when null. | `string` |
| `domain_prefix` | Hosted-UI domain prefix. Default `"auth"`. | `string` |
| `allow_self_signup` | Whether users can sign themselves up (pool-wide). Default `true`. | `bool` |
| `mfa_configuration` | `OFF`, `OPTIONAL`, or `ON`. Default `"OFF"`. | `string` |
| `password_policy` | Password policy overrides. Defaults match doxchange's proven config. | `object(...)` |
| `clients` | Consumer app clients to create, keyed by logical name. Empty by default. | `map(object(...))` |
| `groups` | Optional Cognito groups (coarse, cosmetic relative to the DynamoDB privilege system). | `map(object(...))` |
| `baseline_groups` | Group names every newly-confirmed user is added to. | `list(string)` |
| `create_identity_pool` | Whether to create an identity pool for AWS credential vending. Default `false`. | `bool` |
| `identity_pool_authenticated_role_policy_arns` | Policy ARNs for the identity pool's authenticated role. | `list(string)` |
| `ses_configuration` | Optional SES identity for branded emails. Defaults to Cognito's own email service. | `object(...)` |
| `tenancy_mode` | `"single"` (default) or `"multi"`. | `string` |
| `tenants` | Tenant catalog, keyed by tenantId. Only meaningful in `"multi"` mode. | `map(object(...))` |
| `roles` | Role catalog. Defaults to a minimal `member`/`admin` catalog. | `map(object(...))` |
| `default_role_id` | Role every newly-confirmed user is assigned. Default `"member"`. | `string` |
| `create_admin_panel` | Whether to provision the bundled admin panel. Default `true`. | `bool` |
| `admin_panel_domain_prefix` | Admin panel domain prefix. Default `"admin"`. | `string` |
| `tags` | Additional tags to apply to created resources. | `map(string)` |

## Outputs

| Name | Description |
| --- | --- |
| `user_pool_id` | Cognito user pool ID. |
| `user_pool_arn` | Cognito user pool ARN. |
| `issuer_url` | OIDC issuer URL — wire into your own app's `http_api` `jwt_authorizers`. |
| `hosted_ui_domain` | Cognito hosted-UI custom domain. |
| `hosted_ui_url` | Base HTTPS URL for the hosted UI. |
| `client_ids` | Map of consumer app client IDs, keyed as in `var.clients`. |
| `identity_pool_id` | Identity pool ID, or null when `create_identity_pool` is false. |
| `admin_panel_url` | Base HTTPS URL for the bundled admin panel, or null when disabled. |
| `admin_api_invoke_url` | Invoke URL for the bundled admin API, or null when disabled. |
| `admin_panel_client_id` | Cognito app client ID for the admin panel, or null when disabled. |

## Testing

- `tests/*.tftest.hcl` — mock-provider contract tests, one file per slice
  (identity, RBAC/tenancy, Lambdas, admin API, admin panel hosting).
- `examples/aws/cognito_auth/` — a runnable example.
- `tests/aws/cognito_auth/run.sh` — a provider-backed suite exercising a real
  deployment end to end.
