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

## Update / rollout behavior

All three functions set `publish = true`, so every `terraform apply` that
changes the deployed code creates a new numbered Lambda version (not just an
update to `$LATEST`) -- version history and one-command rollback (`aws lambda
update-function-code` /
`aws lambda update-alias --function-version <n>` if an alias is introduced
later) are available even though nothing currently points at those versions
directly.

That said, **there is no gradual/canary rollout today**. `lambda_config` (the
two Cognito triggers) and the admin-api's `http_api` integration both
reference the unqualified function ARN, i.e. always `$LATEST`. In practice
this means:

- A new invocation after deploy gets the new code immediately.
- An already-warm execution environment mid-invocation when the update lands
  finishes on the code version it started with -- Lambda doesn't kill
  in-flight invocations to switch them to new code.
- There is no traffic-shifting window and no automatic rollback on error
  rate; a bad deploy affects 100% of new invocations right away.

If gradual rollout becomes a real requirement, the standard Lambda pattern is
a `aws_lambda_alias` per function with `routing_config` weights shifted
across a deploy, with `lambda_config`/the API Gateway integration pointed at
the alias ARN instead of the function's unqualified ARN. Not implemented
here -- flagging it as a deliberate scope decision, not an oversight.
