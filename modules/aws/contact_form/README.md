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

## Lambda source

Lambda source is consumed from `@vln-devsecops/contact-form-lambda` on GitHub
Packages rather than vendored here, so version bumps flow through Dependabot
PRs on `lambda-build/package.json`. A `null_resource` installs the package at
apply time; `archive_file` then zips the installed `dist/` output. Contract
tests mock the archive provider, so they don't require a live npm install.

To install locally before running `terraform validate`/`terraform test`:

```sh
npm install --prefix modules/aws/contact_form/lambda-build
```

This requires `NODE_AUTH_TOKEN` (a PAT with `read:packages` scope, or
`GITHUB_TOKEN` in CI) set for the `@vln-devsecops` scope per
`lambda-build/.npmrc`.

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
