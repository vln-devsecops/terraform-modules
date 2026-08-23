# aws/vlinder_auth

A self-provisioning Cognito auth component: a consumer supplies an app id and
the unavoidable AWS plumbing (an existing Route 53 zone and a us-east-1 ACM
certificate — no module in this repo can conjure those) and gets back a
working Cognito-backed signup/login flow, RBAC, and, by default, a hosted
admin panel. No Lambda ARNs, no DynamoDB tables, and no second API to wire by
hand. `auth_profile` scales this down to just the login backend or just
identity + RBAC for adopters bringing their own frontend — see Auth profiles
below.

```hcl
module "auth" {
  source = "git::https://github.com/vln-devsecops/terraform-modules.git//modules/aws/vlinder_auth?ref=v0.1"

  app_name                = "myapp"
  deployment_environment  = "prod"
  route53_zone_id         = "Z1234567890"
  acm_certificate_arn     = "arn:aws:acm:us-east-1:123456789012:certificate/example"

  # everything below is optional, sanely defaulted
}
```

The `acm_certificate_arn` must cover the single hostname this module derives
(`auth.<zone>` by default, via `domain_prefix`) — a wildcard cert from
[`aws/acm_certificate`](../acm_certificate) is the simplest way to get that.

## Branding

There is no Terraform-level branding surface. The auth site is a real
first-party SPA (not Cognito's hosted UI), so branding lives in the SPA build
itself — it reads its theme at runtime via `ui-auth`'s `theme.ts` mechanism
(CSS custom properties) in `node-vlinder-auth`. Override the theme there
rather than through this module.

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

## Auth profiles

`auth_profile` picks which optional layers this module provisions, from most
to least. Each profile is a strict subset of the one above it:

| `auth_profile` | Identity + RBAC | Public auth API (login/session backend) | Admin API + panel | Auth-site CloudFront/S3/SPA shell |
| --- | :---: | :---: | :---: | :---: |
| `"full"` (default) | yes | yes | yes | yes — serves both `/` and `/admin` |
| `"auth_api"` | yes | yes | no | yes — serves `/` only; bring your own admin UI against the RBAC table and Cognito Admin APIs |
| `"identity_only"` | yes | no | no | no — bring your own everything |

Identity (the Cognito user pool) and RBAC/tenancy (the role catalog and the
DynamoDB role-assignments table) are unconditional in every profile — see
`issuer_url`, `user_pool_id`, and `role_assignments_table_name` in Outputs
below, which stay populated even in `"identity_only"`. Outputs specific to a
layer that isn't provisioned (`auth_domain`, `auth_url`,
`auth_site_bucket_name`, `admin_panel_url`, `admin_api_invoke_url`,
`auth_site_client_id`) are `null` when that layer is off.

## The auth site (login + admin panel)

Provisioned for the `"full"` and `"auth_api"` profiles. This module owns a
single CloudFront distribution at `auth.<zone>` (S3 + Origin Access Control,
no Cognito hosted UI involved) serving one SPA that covers both the public
login screens (`/`) and, in the `"full"` profile, the admin panel (`/admin`),
authenticated through one Cognito app client (`auth_site`) shared by both.
There's no self-signup client-side for the admin routes — Cognito's
`admin_create_user_config` is pool-wide, so the real security boundary is the
admin API's own privilege checks, not which client or route a caller came in
through. Tenant-scoped callers (`:own` privileges) see only their own
tenant's users; global-scoped callers (`:*` privileges) see across all
tenants.

Two same-origin API behaviors on the same distribution, ordered so
`/api/v1/auth*` never falls through to the admin API:

- **`/api/v1/auth*`** → the public, unauthenticated auth API (identify,
  password, signup, confirm, resend, forgot, reset). Cookie-session based
  (`vln_auth_session`, `HttpOnly`), rate-limited per route via
  `auth_api_throttling` — see `doc/auth-api-rate-limiting.md`. Present in
  both the `"full"` and `"auth_api"` profiles.
- **`/api/v1/*`** → the JWT-protected admin API. A CloudFront Function lifts
  the session cookie into a `Bearer` header before forwarding, since the SPA
  can't read an `HttpOnly` cookie to set the header itself — see
  `doc/admin-api-csrf.md` for why that lift is safe. Both API origins are
  also gated by a per-deployment `X-Origin-Verify` secret header, closing off
  direct `execute-api` access that would bypass CloudFront (and any WAF
  attached via `waf_web_acl_arn`). Only present in the `"full"` profile.

The SPA's *built* static assets are delivered by Terraform, so a single
`terraform apply` yields a working site — there is no separate deploy step.
The prebuilt bundle is published to GitHub Packages as
`@vln-devsecops/auth-site` (from `node-vlinder-auth`), pinned via
`site-build/package-lock.json` (the lockfile, not the semver range in
`package.json`, is what pins the resolved version), and installed at apply
time with `npm ci` — the same delivery mechanism as the Lambdas. Terraform
then writes the per-deployment `config.json` (the auth-site app-client id,
the multi-tenant flag, and whether the admin API is enabled — fetched at load
time, since Vite env vars are baked in at build time and can't know these
values yet) into the installed bundle, `aws s3 sync`s it to the S3 origin,
and invalidates CloudFront. SPA version bumps flow through Dependabot PRs
against `site-build/package-lock.json`, exactly like the Lambdas. In the
`"auth_api"` profile the same SPA bundle is still deployed (it serves the
public login screens); its `config.json` tells it there's no admin API to
call, and the SPA's `/admin` page degrades to a "not enabled" notice instead
of calling a backend that doesn't exist.

Because the SPA is installed and synced at apply time, the apply host needs
Node + npm (already required for the Lambdas) and the AWS CLI, plus a GitHub
token with `read:packages` for the `@vln-devsecops` scope.

## Security defaults

`allow_self_signup` defaults to `true` and `mfa_configuration` defaults to
`"OFF"` — an open, low-friction signup flow rather than a locked-down one.
That's a deliberate default for this module's primary use case (a new
product standing up its own auth from scratch), not a recommendation for
every deployment:

- `allow_self_signup = true` matches a normal SaaS signup flow. Set it to
  `false` for invite-only products, where `admin_create_user_config` (via
  the admin API's own privilege checks, not the client or route used to
  authenticate — see above) becomes the only way to create users.
- `mfa_configuration = "OFF"` avoids adding enrollment friction to every
  consuming app by default, since not all of them carry data sensitive
  enough to warrant it. Set it to `"OPTIONAL"` or `"ON"` per environment
  (typically `prod`) once an app's risk profile calls for it — this is a
  pool-wide setting, so it can't be scoped to a subset of users.

Both are per-deployment `module` block overrides, so a stricter posture for
one app doesn't have to affect another. `advanced_security_mode`,
`auth_api_throttling`, `waf_web_acl_arn` (see `doc/auth-api-rate-limiting.md`
for the first two), and `password_policy` are the other security-relevant
knobs worth reviewing before a production launch.

## Inputs

| Name | Description | Type |
| --- | --- | --- |
| `app_name` | Application name prefix. | `string` |
| `deployment_environment` | Deployment environment suffix. | `string` |
| `route53_zone_id` | Route53 hosted zone ID serving the derived auth site hostname. | `string` |
| `acm_certificate_arn` | ACM certificate ARN in `us-east-1` covering the derived auth site hostname. | `string` |
| `cloudfront_price_class` | CloudFront price class for the auth site distribution. Default `"PriceClass_100"`. | `string` |
| `waf_web_acl_arn` | ARN of a `us-east-1` WAF web ACL to associate with the auth site distribution. Default `null` (no WAF). | `string` |
| `auth_site_force_destroy` | Whether the auth site S3 bucket can be force-destroyed while non-empty. Default `false`; live/ephemeral test suites should set `true`. | `bool` |
| `user_pool_deletion_protection` | `"ACTIVE"` or `"INACTIVE"` for the Cognito user pool. Default `"ACTIVE"`; ephemeral test suites should set `"INACTIVE"`. | `string` |
| `role_assignments_deletion_protection_enabled` | Whether to enable DynamoDB deletion protection on the role-assignments table. Default `true`; ephemeral test suites should set `false`. | `bool` |
| `domain_prefix` | Auth site domain prefix: `"${domain_prefix}.<zone-name>"`. Default `"auth"`. | `string` |
| `allow_self_signup` | Whether users can sign themselves up (pool-wide). Default `true`. | `bool` |
| `mfa_configuration` | `OFF`, `OPTIONAL`, or `ON`. Default `"OFF"`. | `string` |
| `password_policy` | Password policy overrides. Defaults match doxchange's proven config. | `object(...)` |
| `advanced_security_mode` | Cognito threat protection: `AUDIT`, `ENFORCED`, or `OFF`. Default `"OFF"` -- AUDIT/ENFORCED require a paid Cognito feature plan (billed per MAU, same rate either mode). See `doc/auth-api-rate-limiting.md`. | `string` |
| `auth_api_throttling` | Per-route throttle limits (`burst_limit`, a request count; `rate_limit`, requests/second) applied to the public `/api/v1/auth*` routes. Defaults `burst_limit=10`, `rate_limit=5` -- no extra AWS cost. See `doc/auth-api-rate-limiting.md`. | `object(...)` |
| `clients` | Consumer app clients to create, keyed by logical name. The auth site's own client is always created separately and doesn't need an entry here. Empty by default. | `map(object(...))` |
| `groups` | Optional Cognito groups (coarse, cosmetic relative to the DynamoDB privilege system). | `map(object(...))` |
| `baseline_groups` | Group names every newly-confirmed user is added to. | `list(string)` |
| `create_identity_pool` | Whether to create an identity pool for AWS credential vending. Default `false`. | `bool` |
| `identity_pool_authenticated_role_policy_arns` | Policy ARNs for the identity pool's authenticated role. | `list(string)` |
| `ses_configuration` | Optional SES identity for branded emails. Defaults to Cognito's own email service. | `object(...)` |
| `tenancy_mode` | `"single"` (default) or `"multi"`. | `string` |
| `tenants` | Tenant catalog, keyed by tenantId. Only meaningful in `"multi"` mode. | `map(object(...))` |
| `roles` | Role catalog. Defaults to a minimal `member`/`admin` catalog. | `map(object(...))` |
| `default_role_id` | Role every newly-confirmed user is assigned. Default `"member"`. | `string` |
| `auth_profile` | Which optional layers to provision: `"full"` (default), `"auth_api"`, or `"identity_only"`. See Auth profiles above. | `string` |
| `tags` | Additional tags to apply to created resources. | `map(string)` |

## Outputs

| Name | Description |
| --- | --- |
| `user_pool_id` | Cognito user pool ID. |
| `user_pool_arn` | Cognito user pool ARN. |
| `issuer_url` | OIDC issuer URL — wire into your own app's `http_api` `jwt_authorizers`. |
| `auth_domain` | Auth site domain (CloudFront alias for the login and admin SPA), or null when `auth_profile` is `"identity_only"`. |
| `auth_url` | Base HTTPS URL for the auth site (login SPA), or null when `auth_profile` is `"identity_only"`. |
| `client_ids` | Map of consumer app client IDs, keyed as in `var.clients`. |
| `identity_pool_id` | Identity pool ID, or null when `create_identity_pool` is false. |
| `admin_panel_url` | URL for the admin panel within the auth site (`<auth_url>/admin`), or null unless `auth_profile` is `"full"`. |
| `admin_api_invoke_url` | Invoke URL for the bundled admin API, or null unless `auth_profile` is `"full"`. |
| `auth_site_client_id` | Cognito app client ID for the bundled auth site, or null when `auth_profile` is `"identity_only"`. |
| `auth_site_bucket_name` | S3 bucket name for the auth site SPA static assets, or null when `auth_profile` is `"identity_only"`. |
| `role_assignments_table_name` | DynamoDB table name backing user role assignments. |

## Testing

- `tests/*.tftest.hcl` — mock-provider contract tests, one file per slice
  (identity, RBAC/tenancy, Lambdas, auth API, admin API, auth site
  distribution/routing, auth site deploy).
- `examples/aws/vlinder_auth/` — a runnable example.
- `tests/aws/vlinder_auth/run.sh` — a provider-backed suite exercising a real
  deployment end to end.
