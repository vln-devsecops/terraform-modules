# Vendored Lambda source (bootstrap placeholders)

The three subdirectories here (`post-confirmation`, `pre-token-generation`,
`admin-api`) are what `main.tf` zips via `archive_file` to deploy this
module's Lambda functions -- no S3 deployment bucket, no separate build step
at `terraform apply` time.

**Right now these are minimal placeholder handlers**, matching the pattern
`aws/lambda`'s own built-in "echo" fallback uses for bootstrapping. The real
implementation -- fully TDD'd, with the tenant/role-assignment resolution,
privilege injection, and admin-API authorization logic -- lives in
[`node-vlinder-auth`](https://github.com/vln-devsecops/node-vlinder-auth)'s
`packages/lambda-src`. That repo's CI is responsible for building and
vendoring the real compiled output into these directories (tracked as a
follow-up; see that repo's `README.md`).

Do not hand-edit these placeholder files expecting them to gain real
behavior -- update `node-vlinder-auth` and let its vendoring pipeline refresh
this directory instead.
