# aws/vlinder_auth CloudFront Function runtime smoke test

Live-runtime coverage for the two `cloudfront-js-2.0` CloudFront Functions in
`modules/aws/vlinder_auth` (`admin_api_rewrite`, `spa_viewer_request`).

## Why this exists

`cloudfront-js-2.0` is AWS's own curated JS subset -- not a standard
ECMAScript version -- and it rejects ES2020+ syntax (optional chaining `?.`,
nullish coalescing `??`) with a parse-time `SyntaxError`. When that happens,
CloudFront serves a generic 503 to every viewer request through the affected
behavior, before the origin is ever reached: no Lambda invocation, no log,
nothing pointing at the cause. `admin_api_rewrite.js` shipped with `?.` and
silently broke the entire admin panel this way for months, only root-caused
via a live `aws cloudfront test-function` call.

The module's build pipeline (`templates/src/*.js` -> esbuild -> committed
`templates/dist/*.js`, see `doc/cloudfront-js-runtime-compatibility.md`) and
`terraform test`'s string-based assertions both catch the *build-time*
symptom (does the compiled output still contain `?.`/`??`), but neither can
actually execute `cloudfront-js-2.0` -- `terraform test`'s mock provider
never runs real JS. This suite closes that gap: it deploys the exact
committed `templates/dist/*.js` files as real, unassociated CloudFront
Function objects and calls `aws cloudfront test-function` against them with
synthetic viewer-request events, asserting both that the runtime accepts the
code (no `FunctionErrorMessage`) and that the returned request/response
matches what each function is supposed to do.

## What it creates

Two bare `aws_cloudfront_function` resources, `publish = false`
(DEVELOPMENT stage only) -- deliberately **no** distribution, no S3 origin,
no Cognito, nothing else. Unlike `tests/aws/vlinder_auth/` (which deploys
the full module, including a real Route53-validated ACM certificate and
CloudFront distribution, and takes minutes), this suite is fast and cheap:
CloudFront Functions cost nothing to create or keep unassociated, and
`TestFunction` calls are effectively free too.

## What it checks

For `admin_api_rewrite`:

- a `GET` with a `vln_auth_session` cookie: no runtime error, and the
  cookie gets correctly lifted into a `Bearer` `Authorization` header
- a state-changing method (`PATCH`) with no CSRF cookie/header: no runtime
  error, rejected with `statusCode: 403`
- a `PATCH` with matching `vln_auth_csrf` cookie and `x-vln-csrf-token`
  header: no runtime error, passes through as the modified request

For `spa_viewer_request`:

- `/admin` rewrites to `/admin/index.html`
- `/` rewrites to `/index.html`
- a static asset path (`/assets/app.js`) passes through unchanged

Every case asserts `FunctionErrorMessage` is absent -- that is the actual
regression guard for the bug class described above, independent of whatever
else the case is also checking.

## Environment

No suite-specific variables beyond the shared `_lib.sh` contract
(`TF_VAR_name_suffix`, `TF_VAR_aws_region`) and working AWS credentials with
`cloudfront:CreateFunction`/`UpdateFunction`/`PublishFunction`/
`DeleteFunction`/`DescribeFunction`/`GetFunction`/`TestFunction`.
