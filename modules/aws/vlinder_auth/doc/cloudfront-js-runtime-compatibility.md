# `cloudfront-js-2.0` runtime compatibility

## What `cloudfront-js-2.0` actually is

Both CloudFront Functions in this module (`aws_cloudfront_function.spa_viewer_request`
and `aws_cloudfront_function.admin_api_rewrite` in `main.tf`) declare
`runtime = "cloudfront-js-2.0"`. That string names AWS's own hand-curated
JavaScript feature subset, **not** a standard ECMAScript version. It is
roughly ES5.1 plus specifically: `let`/`const`, template literals, arrow
functions, rest parameters, the `**` operator, and `async`/`await`. It does
**not** include ES2020+ features — most relevantly, optional chaining (`?.`)
and nullish coalescing (`??`) are unsupported and rejected outright with a
parse-time `SyntaxError`.

## Why that failure mode is dangerous

A CloudFront Function that fails to parse doesn't fail at `terraform apply`,
and it doesn't fail per-request with a catchable error either: CloudFront
serves its own generic 503 HTML page for **every single viewer request**
through the behavior that function is attached to, before the origin is ever
reached. There is no Lambda invocation, so there is no CloudWatch log
pointing at the cause — nothing but silent, total, immediate failure for
every viewer, indistinguishable from the outside from an unrelated outage.

This actually happened: `admin_api_rewrite.js` shipped with `a?.b` optional
chaining and silently broke the entire admin panel for months. It was
root-caused by reproducing the exact `SyntaxError` with a live
`aws cloudfront test-function` call against the deployed function (see the
history of `templates/src/admin_api_rewrite.js` and
`tests/admin_api.tftest.hcl`'s `admin_api_rewrite_avoids_syntax_cloudfront_js_2_0_rejects`
run block).

## The fix: transpile, don't hand-avoid

The first fix rewrote the three `a?.b` sites as `a && a.b` by hand. That
works, but it's fragile — it relies on every future contributor remembering,
forever, never to write ES2020+ syntax in these two files specifically, with
no tooling enforcing it beyond a regex-based `terraform test` assertion.

The durable fix, in place as of this doc: contributors write normal, modern
JavaScript in `templates/src/*.js`, and a small build step transpiles it down
to what `cloudfront-js-2.0` actually accepts, writing the result to
`templates/dist/*.js` — which is what `main.tf`'s `aws_cloudfront_function`
resources actually read via `file()`.

### `edge-functions-build/`

A self-contained npm-managed directory, following the same pattern as this
module's other two build-requiring artifacts (`lambda-build/`, `site-build/`):

- `package.json` — `esbuild` as the sole devDependency.
- `build.mjs` — for every `.js` file in `../templates/src/`, runs
  `esbuild.transformSync(source, { target: ['es2019'], loader: 'js', sourcefile: name })`
  and writes the result to `../templates/dist/<name>`, prefixed with a
  generated-file header comment.

`es2019` is the target deliberately: it's the newest standard ECMAScript
version that still contains everything `cloudfront-js-2.0` natively supports
(arrow functions, template literals, `let`/`const`, async/await, rest
params) while sitting below ES2020, where `?.`/`??` were introduced. That
makes esbuild downlevel exactly the syntax that needs downleveling (e.g.
`a?.b` becomes a `== null` guard temp-variable pattern) without also
rewriting syntax `cloudfront-js-2.0` already handles natively, which a lower
target such as `es5` would do unnecessarily.

Regenerate after editing anything in `templates/src/`:

```sh
cd modules/aws/vlinder_auth/edge-functions-build
npm ci
npm run build
```

### Why `templates/dist/` is committed, unlike `lambda-build`/`site-build`

`lambda-build/` and `site-build/` are gitignored on purpose: they fetch
large, frequently-changing, externally-published npm packages fresh at
`terraform apply` time via `local-exec` (see the root-level
`doc/local-exec-build-triggers.md` once it's synced into this branch from
`main`). Committing their resolved output would mean committing a copy of
someone else's package tree.

`templates/dist/*.js` is different in a way that matters mechanically, not
just stylistically: `aws_cloudfront_function.*.code` reads its file directly
via Terraform's own `file()` function, which is evaluated for real even under
`terraform test`'s mock provider. `tests/admin_api.tftest.hcl` already relies
on this — `admin_api_rewrite_enforces_double_submit_csrf` and
`admin_api_rewrite_avoids_syntax_cloudfront_js_2_0_rejects` both assert
against the literal string content of `aws_cloudfront_function.admin_api_rewrite[0].code`.
There is no apply-time hook in the `terraform test` path (the `modules` job in
`.github/workflows/ci_terraform.yml` has no Node/npm setup at all) where a
build step could run before that `file()` call happens. So the generated
files must already exist in the checkout — which means committing them, and
enforcing freshness independently in CI, rather than generating them at
apply time the way `lambda-build`/`site-build` do.

### CI freshness enforcement

`.github/workflows/ci_terraform.yml` sets up Node, runs
`npm ci --prefix modules/aws/vlinder_auth/edge-functions-build`, rebuilds,
and runs `git diff --exit-code -- modules/aws/vlinder_auth/templates/dist`.
That fails the build if committed `dist/` doesn't match a fresh build of
`src/` — catching both a hand-edited `dist/` file and a `src/` edit that
someone forgot to rebuild.

`admin_api_rewrite_avoids_syntax_cloudfront_js_2_0_rejects` in
`tests/admin_api.tftest.hcl` stays in place as a second, independent layer:
with the build pipeline in place, `templates/src/*.js` is free to use `?.`/
`??` again, and the guarantee that the *deployed* code never contains them
now comes from the build (`es2019` target) rather than from a developer
manually avoiding the syntax. The test is defense-in-depth against someone
bypassing the build system entirely (e.g. hand-editing `templates/dist/`
directly) — a case the CI diff-check above also catches independently, but
belt-and-suspenders costs nothing here.
