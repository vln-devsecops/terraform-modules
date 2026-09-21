# aws/static_site CloudFront Function runtime smoke test

Live-runtime coverage for the single `cloudfront-js-2.0` CloudFront Function
in `modules/aws/static_site` (`aws_cloudfront_function.viewer_request`,
rendered from `templates/viewer_request.js.tftpl`).

## Why this exists

This is preemptive coverage, not a bug fix: as currently written,
`viewer_request.js.tftpl` is plain ES5.1-style `var`-only code with no
`?.`/`??`, so there is no known live incompatibility here today. But
`tests/aws/vlinder_auth_edge_functions/` proved the blind spot this pattern
closes is real: `cloudfront-js-2.0` is AWS's own curated JS subset, not a
standard ECMAScript version, and a CloudFront Function that fails to parse
at the runtime level still creates successfully via the Terraform provider
-- the failure only shows up when the runtime actually tries to run it. One
of `modules/aws/vlinder_auth`'s two functions shipped with an unguarded `?.`
and silently 503'd an entire admin panel for months before that was
root-caused with a live `aws cloudfront test-function` call, because
`terraform test`'s mock provider can never execute a CloudFront Function's
actual JS runtime. This suite closes the same gap here, before an incident
forces it.

## Why two rendered variants

Unlike `vlinder_auth`'s two functions -- committed, static
`templates/dist/*.js` build artifacts that are the same bytes in every
deployment -- `static_site`'s function is a genuine Terraform *template*:
`templatefile("${path.module}/templates/viewer_request.js.tftpl", {...})`
interpolates `basic_auth_enabled`, `basic_auth_header`, `basic_auth_realm`,
`enable_pretty_urls`, and `pretty_url_exceptions` per module consumer. There
is no single static file to deploy and test. Instead, this suite's
`main.tf` copies the exact `templatefile()` call shape (and the same
`base64encode`/`jsonencode` derivations) from
`modules/aws/static_site/main.tf`'s `locals` block, driven by two
representative variant configs that exercise both branches of both
conditionals:

- `both_enabled`: basic auth on (fixture username/password/realm) and
  pretty URLs on (with one exception path).
- `both_disabled`: both features off.

## What it creates

Two bare `aws_cloudfront_function` resources
(`aws_cloudfront_function.viewer_request["both_enabled"]` and
`["both_disabled"]`), `publish = false` (DEVELOPMENT stage only) --
deliberately **no** distribution, no S3 origin, no ACM certificate, no
Route53 record. Unlike `tests/aws/static_site/` (which deploys the full
module, including a real Route53-validated ACM certificate and CloudFront
distribution, and takes minutes), this suite is fast and cheap: CloudFront
Functions cost nothing to create or keep unassociated, and `TestFunction`
calls are effectively free too. `tests/aws/static_site/` is left untouched
by this suite and never calls `aws cloudfront test-function` itself -- it
only checks distribution aliases/status and DNS records.

## What it checks

For `both_enabled`:

- a request with no `Authorization` header: no runtime error, rejected with
  `statusCode: 401` and a `www-authenticate` challenge containing the
  configured realm
- a request with the correct `Authorization: Basic <base64(user:pass)>`
  header: no runtime error, passes through as the modified request (no
  `statusCode`), proving the auth check passed
- using that same correctly-authorized request, the pretty-URL branch: a
  trailing-slash `uri` (`/docs/`) rewrites to `/docs/index.html`; an
  extensionless `uri` not in `pretty_url_exceptions` (`/about`) rewrites to
  `/about/index.html`; `/healthz`, which IS in `pretty_url_exceptions`,
  passes through unchanged despite being extensionless

For `both_disabled`:

- a request with no `Authorization` header: no runtime error, passes
  through completely unchanged -- proving basic auth is genuinely off, not
  just permissive
- a request with an extensionless `uri`: no runtime error, `uri` unchanged
  -- proving pretty-url rewriting is genuinely off

Every case asserts `FunctionErrorMessage` is absent -- that is the actual
regression guard this suite exists for, independent of whatever else the
case is also checking, and it's what would catch a future edit to
`viewer_request.js.tftpl` that introduces syntax `cloudfront-js-2.0`
rejects (e.g. optional chaining or nullish coalescing).

## Environment

No suite-specific variables beyond the shared `_lib.sh` contract
(`TF_VAR_name_suffix`, `TF_VAR_aws_region`) and working AWS credentials with
`cloudfront:CreateFunction`/`UpdateFunction`/`PublishFunction`/
`DeleteFunction`/`DescribeFunction`/`GetFunction`/`TestFunction`.
