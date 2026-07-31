# modules/aws/contact_form

Self-provisioning contact-form backend: a DynamoDB table plus two Lambda
functions, each behind its own Function URL.

- **submit** -- public (`authorization_type = "NONE"`), reCAPTCHA v3-gated.
  Never hard-rejects a submission on a bad reCAPTCHA verdict; the Lambda
  stores it tagged `status: "spam"` instead of dropping it, so a false
  positive is still reviewable. This module only provisions the
  infrastructure; that behavior lives in the Lambda source
  (`@vln-devsecops/contact-form-lambda`, published from
  [`node-contact-form`](https://github.com/vln-devsecops/node-contact-form)).
- **admin** -- `authorization_type = "AWS_IAM"`. No app-level auth code at
  all; the Function URL's IAM auth is the entire access-control boundary.
  Callers must SigV4-sign requests and be listed in
  `admin_allowed_principal_arns` (AWS_IAM auth alone does not implicitly
  grant any caller invoke access).

## Permissions your apply role needs

This module creates resource types many roots have never provisioned before, so
a role that applies the rest of a typical site's infrastructure is usually
missing several of these. None of the gaps are visible to `terraform validate`,
`terraform plan` or `terraform test` -- they surface only on a real apply, one
at a time, as the apply reaches each resource.

Grant all of the following up front rather than discovering them across several
failed applies:

- **DynamoDB** -- the table. `AmazonDynamoDBFullAccess` covers it.
- **KMS management plane** -- creating, tagging and aliasing the CMKs.
  `AWSKeyManagementServicePowerUser` is the closest AWS-managed policy; note
  there is no `*FullAccess` tier for KMS.
- **KMS data plane** -- `kms:GenerateDataKey`, `Decrypt`, `Encrypt`,
  `CreateGrant` and friends. `AWSKeyManagementServicePowerUser` grants **none**
  of these. Creating a Secrets Manager secret, a DynamoDB table or a Lambda with
  encrypted environment variables under a customer-managed key requires the
  calling principal to be able to *use* that key for envelope encryption, not
  merely to have created it. Without these the apply fails with a bare
  `Access to KMS is not allowed`.
- **`iam:CreatePolicy` scoped to `iampolicy-ddb-*`** -- the composed
  `modules/aws/dynamodb` creates its own read/write policy named
  `iampolicy-ddb-<app>-<env>-<function>-rw`, which does **not** start with your
  `app_name`. A role whose IAM permissions are scoped to `<app_name>*` resource
  patterns will not match it.
- **Secrets Manager** -- the reCAPTCHA secret. `SecretsManagerReadWrite` covers
  it.

## Lambda source

Lambda source is consumed from `@vln-devsecops/contact-form-lambda` on GitHub
Packages rather than vendored here, so version bumps flow through Dependabot
PRs on `lambda-build/package.json`. A `null_resource` installs the package at
apply time; `archive_file` then zips the installed `dist/` output. Contract
tests mock the archive provider, so they don't require a live npm install.

Both functions share **one** zip. The build produces two self-contained bundles
at `dist/submit/handler.js` and `dist/admin/handler.js`, so the archive covers
the whole `dist/` tree and each function points at its own subdirectory via
`handler = "<subdir>/handler.handler"`. There is no per-function zip and no
per-function `source_code_hash`.

The install runs on **every** apply, but the command itself skips `npm install`
when the target directory is already present. Keying the trigger on
`package.json`'s content instead would be wrong on ephemeral CI runners: state
would say "already installed" while the runner's filesystem is empty, and
`archive_file` would then fail reading a directory that only ever existed on a
previous runner's disk. Reinstalling unconditionally would be equally wrong --
two `npm install` runs of identical content produce different zip bytes
(fresh timestamps and file ordering), so every apply would show a spurious
Lambda redeployment. Running the provisioner every time while making the work
itself idempotent is what avoids both.

To install locally before running `terraform validate`/`terraform test`:

```sh
npm install --prefix modules/aws/contact_form/lambda-build
```

This requires `NODE_AUTH_TOKEN` (a PAT with `read:packages` scope, or
`GITHUB_TOKEN` in CI) set for the `@vln-devsecops` scope per
`lambda-build/.npmrc`.

## Resource naming

The KMS key/alias, the reCAPTCHA secret, the IAM roles/policies and the two
Lambda functions all include a random per-stack suffix
(`random_string.unguessable`, generated once and persisted in this stack's own
state) after `${app_name}-${deployment_environment}`. Without it, two stacks
sharing those values -- concurrent PR-preview stacks, or a preview re-applied
while a prior destroy's resources are still inside their deletion window --
would fight over identical AWS resource names (KMS keys and Secrets Manager
secrets are especially prone to this, since a deleted one doesn't free its
name/alias until its deletion window elapses). Read the names from this
module's outputs rather than reconstructing them.

## Post-apply step

Terraform creates the reCAPTCHA secret with a placeholder value only. Set the
real reCAPTCHA v3 secret key out of band before submissions can be verified:

```sh
aws secretsmanager put-secret-value \
  --secret-id "$(terraform output -raw recaptcha_secret_arn)" \
  --secret-string "<real reCAPTCHA v3 secret key>"
```

## Usage

```hcl
module "contact_form" {
  source = "github.com/vln-devsecops/terraform-modules//modules/aws/contact_form?ref=v0.1"

  app_name                = "myapp"
  deployment_environment  = "prod"
  admin_allowed_principal_arns = [
    "arn:aws:iam::123456789012:user/ronald",
  ]

  submit_cors = {
    allow_methods = ["POST"]
    allow_origins = ["https://myapp.example.com"]
  }
}
```

## Inputs

See `variables.tf`. Only `app_name` and `deployment_environment` are
required; everything else has a sane default.

## Outputs

See `outputs.tf`: `table_name`/`table_arn`, `submit_function_url`,
`admin_function_url`, `recaptcha_secret_arn`, and both functions' names.
