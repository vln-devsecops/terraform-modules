# aws/cognito_auth example

Two illustrative scenarios:

- `module.auth` — single-tenant (the default), minimal input.
- `module.auth_multi_tenant` — multi-tenant, with a custom role catalog
  including a cross-tenant `super-admin` role.

In practice these would target different Route53 zones: `cognito_auth`
derives `auth-<zone>` and `admin-<zone>` hostnames directly from the zone
name, which would collide if both scenarios really pointed at the same zone.
This example is validated, not applied, in CI (see the repo's `ci_terraform.yml`
`examples` job), so that collision never actually matters here.
