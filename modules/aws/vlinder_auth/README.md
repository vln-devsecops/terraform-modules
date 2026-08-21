# aws/vlinder_auth

A self-provisioning Cognito auth component: a consumer supplies an app id and
the unavoidable AWS plumbing (an existing Route 53 zone and a us-east-1 ACM
certificate — no module in this repo can conjure those) and gets back a
working Cognito-backed signup/login flow, RBAC, and a hosted admin panel. No
Lambda ARNs, no DynamoDB tables, and no second API to wire by hand.

```hcl
module "auth" {
  source = "git::https://github.com/vln-devsecops/terraform-modules.git//modules/aws/vlinder_auth?ref=v0.1"

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
(`auth.<zone>` for the hosted UI, `admin.<zone>` for the bundled admin panel)
— a wildcard cert from [`aws/acm_certificate`](../acm_certificate) is the
simplest way to get that.

## Branding

`logo_base64` and `css` are the only overridable branding surface, and both
default to a generic placeholder (a plain color scheme, no logo) — not any
particular organization's real branding. Cognito's hosted-UI CSS
customization only recognizes a fixed, AWS-defined set of selectors; `css`
can target any of:

`background-customizable`, `banner-customizable`, `idpButton-customizable`,
`idpDescription-customizable`, `inputField-customizable`,
`label-customizable`, `legalText-customizable`, `submitButton-customizable`,
`textDescription-customizable`, `errorMessage-customizable`

There's no way to add app-specific prefixed class names here (unlike the
`ui-auth` React components in `node-vlinder-auth`, which do use normal
app-controlled class names) — this is entirely AWS's fixed vocabulary for
the hosted UI page.

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

### Multi-tenant with a custom role catalog

```hcl
module "auth" {
  source = "git::https://github.com/vln-devsecops/terraform-modules.git//modules/aws/vlinder_auth?ref=v0.1"

  app_name                = "myapp"
  deployment_environment  = "prod"
  route53_zone_id         = "Z1234567890"
  acm_certificate_arn     = "arn:aws:acm:us-east-1:123456789012:certificate/example"

  tenancy_mode = "multi"
  tenants = {
    acme-corp = {
      name         = "Acme Corp"
      email_domain = "acme.example.com"
    }
    globex = {
      name         = "Globex"
      email_domain = "globex.example.com"
    }
  }

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
}
```

## The bundled admin panel

On by default (`create_admin_panel = true`). Hosted at
`admin.<zone>` via `aws/static_site`, with its own Cognito app client
(no self-signup client-side — Cognito's `admin_create_user_config` is
pool-wide, so the real security boundary is the admin API's own privilege
checks, not which client a caller authenticated through) and its own
`aws/http_api` behind a JWT authorizer pointed at this module's own pool.
Tenant-scoped callers (`:own` privileges) see only their own tenant's users;
global-scoped callers (`:*` privileges) see across all tenants.

The SPA's *built* static assets are delivered by Terraform, so a single
`terraform apply` yields a working site — there is no separate deploy step.
The prebuilt bundle is published to GitHub Packages as
`@vln-devsecops/auth-site` (from `node-vlinder-auth`), pinned in
`site-build/package.json`, and installed at apply time — the same delivery
mechanism as the Lambda. Terraform writes the per-deployment `config.json`
(the auth-site app-client id and the multi-tenant flag — a `config.json`
fetched at load time, since Vite env vars are baked in at build time and can't
know these values yet) into the installed bundle with a `local_file` resource,
then `aws s3 sync`s it to the S3 origin and invalidates CloudFront. SPA version
bumps flow through Dependabot PRs on `site-build/package.json`.

Because the SPA is installed and synced at apply time, the apply host needs
Node + npm (already required for the Lambda) and the AWS CLI, plus a GitHub
token with `read:packages` for the `@vln-devsecops` scope.

## Inputs

| Name | Description | Type |
| --- | --- | --- |
| `app_name` | Application name prefix. | `string` |
| `deployment_environment` | Deployment environment suffix. | `string` |
| `route53_zone_id` | Route53 hosted zone ID serving the derived hostnames. | `string` |
| `acm_certificate_arn` | ACM certificate ARN in `us-east-1` covering both derived hostnames. | `string` |
| `logo_base64` | Base64-encoded hosted-UI logo. Omitted (no custom logo) when null. | `string` |
| `css` | Hosted-UI CSS override. Defaults to a built-in placeholder theme when null. | `string` |
| `domain_prefix` | Hosted-UI domain prefix. Default `"auth"`. | `string` |
| `allow_self_signup` | Whether users can sign themselves up (pool-wide). Default `true`. | `bool` |
| `mfa_configuration` | `OFF`, `OPTIONAL`, or `ON`. Default `"OFF"`. | `string` |
| `password_policy` | Password policy overrides. Defaults match doxchange's proven config. | `object(...)` |
| `advanced_security_mode` | Cognito threat protection: `AUDIT`, `ENFORCED`, or `OFF`. Default `"OFF"` -- AUDIT/ENFORCED require a paid Cognito feature plan (billed per MAU, same rate either mode). See `doc/auth-api-rate-limiting.md`. | `string` |
| `auth_api_throttling` | Per-route throttle limits (`burst_limit`, a request count; `rate_limit`, requests/second) applied to the public `/auth/*` routes. Defaults `burst_limit=10`, `rate_limit=5` -- no extra AWS cost. See `doc/auth-api-rate-limiting.md`. | `object(...)` |
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
- `examples/aws/vlinder_auth/` — a runnable example.
- `tests/aws/vlinder_auth/run.sh` — a provider-backed suite exercising a real
  deployment end to end.
