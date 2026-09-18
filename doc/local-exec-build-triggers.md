# `local-exec` build steps must use an `always_run` trigger, not a content hash

Several modules in this repo shell out to `npm ci`/`npm install` via a `null_resource` +
`provisioner "local-exec"` to build a Lambda or SPA bundle before `data.archive_file` zips it.
This pattern has a specific, non-obvious failure mode on genuinely ephemeral CI runners
(a fresh filesystem on every single run — no persisted `node_modules` between applies),
and it has now been discovered and fixed independently three times: `modules/aws/contact_form`,
`modules/aws/http_api_authorizer`, and `modules/aws/vlinder_auth` (two separate build steps
there — the Lambda package and the SPA package). This doc exists so it isn't rediscovered a
fourth time.

## The trap

The obvious-looking trigger is to key the `null_resource` on the build inputs, so the
provisioner only reruns when something actually changed:

```hcl
triggers = {
  package_json    = filemd5("${path.module}/lambda-build/package.json")
  package_lock    = filemd5("${path.module}/lambda-build/package-lock.json")
  install_present = fileexists("${path.module}/lambda-build/node_modules/@scope/pkg/dist/entry.js") ? "present" : "missing"
}
```

The `install_present` check looks like it should handle "fresh checkout, no `node_modules`
yet" by forcing a rerun. It doesn't, reliably: Terraform evaluates that `fileexists()` check
once, at plan time, *before* the provisioner has run. On the very first apply that actually
installs the package, the value recorded into state is still `"missing"` (the file didn't
exist yet when the trigger was computed), even though the apply then succeeds and the file
exists afterward. On a persistent developer machine, the *next* `terraform apply` re-evaluates
`fileexists()`, now sees `"present"`, diffs against the stored `"missing"`, and self-corrects
with one redundant reinstall — annoying but harmless.

On a genuinely ephemeral CI runner, there is no "next apply on the same filesystem." Every run
starts from a clean checkout with no `node_modules` at all. `fileexists()` evaluates to
`"missing"` again — which now matches what's already in state (also `"missing"`, from the
first run's own quirk above) — so Terraform sees **no trigger change**, skips the provisioner
entirely, and `data.archive_file` then fails with something like:

```text
Error: Archive creation error
error creating archive: error archiving directory: could not archive missing directory:
.../lambda-build/node_modules/@scope/pkg/dist
```

This is exactly what happened on a real `cd_refresh_vlinder_auth_demo` run against
`infra/demo/vlinder_auth` — `vlinder_auth`'s own `null_resource.lambda_package` and
`null_resource.auth_site_package` still used this pattern when every other module in this repo
had already moved off it.

## The fix

Always run the provisioner, and let the *command itself* — not the trigger — decide whether a
reinstall is actually necessary:

```hcl
triggers = {
  always_run = timestamp()
}

provisioner "local-exec" {
  command = "test -d ${path.module}/lambda-build/node_modules/@scope/pkg/dist || npm ci --prefix ${path.module}/lambda-build --ignore-scripts"
}
```

This also avoids a second, separate problem a naive `always_run` + unconditional reinstall
would introduce: two separate `npm install`/`npm ci` runs of byte-identical package content do
**not** produce a byte-identical `archive_file` output (re-extracted files get fresh
timestamps/ordering, changing the zip's hash even though no file's content actually changed).
Always running the provisioner but only reinstalling when the target directory is missing means
`archive_file` re-reads the same untouched files — and produces the same hash — on every apply
where nothing needs to change, and only pays the reinstall (and the one-time hash churn that
comes with it) on a genuinely fresh filesystem. See `modules/aws/contact_form/main.tf`'s
`null_resource.lambda_package` for the fullest version of this reasoning in context, and
`modules/aws/http_api_authorizer/main.tf` / `modules/aws/vlinder_auth/main.tf` for the same
pattern applied elsewhere.

## When this applies

Any `null_resource` + `local-exec` step whose job is to produce a build artifact on local disk
that a later `data.archive_file` (or similar local read) depends on — not just `npm`/Lambda
packaging. If a future module needs an equivalent step, start from this pattern rather than a
content-hash trigger.
