# Admin API CSRF posture

## Why this exists

`templates/src/admin_api_rewrite.js` (the CloudFront viewer-request function on
the `/api/v1/*` behavior) lifts the `vln_auth_session` `HttpOnly` cookie into
a `Bearer` `Authorization` header before forwarding to the admin API's HTTP
API Gateway. The admin API's JWT authorizer only reads the header — the SPA
can't set it itself, since the token is `HttpOnly` — so the edge does it for
every request that carries the cookie.

That lift is a deliberate trade: it converts the admin API from **bearer-token
semantics** (a browser never attaches a bearer token to a request unless JS
puts it there, so a cross-site page has no way to trigger an authenticated
request — CSRF-immune by construction) to **cookie semantics** (the browser
attaches the cookie automatically on any request to the origin, which is
exactly the mechanism CSRF exploits).

## The posture: double-submit, unconditionally

The admin API carries **double-submit CSRF protection, always on** — not
deferred until a form-submittable route appears.

Cookie authentication is the normal case across the whole system now that
cookie-only is the default token delivery for every consuming application's
BFF (see `node-vlinder-auth`'s `doc/rationale.md`), so this gets one posture,
implemented once, reviewed once, rather than a strong default in one place
and a conditional exception here.

`SameSite` alone is not something to lean on as the primary defence either —
it depends on every current and future browser enforcing it correctly.

### Shape

Mirror the scheme the reference BFF uses, so there is one design to review:

1. **A second cookie** alongside `vln_auth_session` — `vln_auth_csrf`,
   `Secure` + `SameSite=Strict`, and deliberately **not** `HttpOnly` so JS can
   read it. Its value is `HMAC(session-id, csrf-secret)` rather than a bare
   random value, so it cannot be forged by anyone who can merely set a cookie
   on the origin. That matters little for a single origin, and costs nothing
   to do properly from the start.
2. **The SPA echoes it back in a custom header** (`X-Vln-Csrf-Token`) on every
   state-changing request. A cross-site `<form>` can neither set a custom
   header nor read a cookie value into JS to forge one, which is the gap this
   closes.
3. **Verification happens at the edge, in `admin_api_rewrite.js`.** That
   function already inspects `request.cookies` and `request.headers` before
   performing the Bearer lift, so it is the natural place to reject (`403`)
   any state-changing request whose header is missing or does not match the
   cookie. CloudFront Functions support only simple synchronous logic, and a
   string comparison is well within that budget.

### Defence in depth that stays

Two things are **kept**, not replaced, now that double-submit is in place:

- **`SameSite=Strict` on `vln_auth_session`** (see `session.ts`'s
  `serializeSessionCookie` in `node-vlinder-auth`). Strict cookies are not
  attached to *any* cross-site request, so in the CSRF scenario the browser
  never sends the session cookie at all. Double-submit is the primary
  defence; this remains a second, independent one.
- **The `admin_api_never_exposes_a_post_route` run block** in
  `tests/admin_api.tftest.hcl`, which asserts against `local.admin_api_routes`
  that no route uses `POST`. Double-submit does not make this redundant. Its
  value now is that adding a form-submittable route becomes a deliberate act
  that fails `terraform test` and forces a second look, rather than something
  that slips in on the assumption that double-submit already covers it.

## Two things worth knowing

- The cookie lift **silently overrides** any client-supplied `Authorization`
  header when the cookie is present. This is intentional — the SPA can't
  accidentally authenticate as a different principal than its own session —
  but it is easy to forget when debugging a request that "ignores" a header
  set by hand.
- The `startswith(route.route_key, "POST ")` check only catches routes
  declared literally as `"POST ..."`. A future catch-all route (an
  `"ANY /{proxy+}"` pattern) would implicitly permit `POST` without matching
  that string, silently defeating the assertion. Nothing in this module uses
  catch-all routes today; if that pattern is ever introduced, this check needs
  revisiting alongside it.

## Status

Implemented, as step 8a of `node-vlinder-auth`'s `doc/plan.md`.

- **This repo (terraform-modules)**: `templates/src/admin_api_rewrite.js`
  (transpiled to `templates/dist/admin_api_rewrite.js` — see
  `doc/cloudfront-js-runtime-compatibility.md` — which is what Terraform
  actually deploys) performs the double-submit check described above, and
  `aws_secretsmanager_secret.admin_api_csrf_secret` in `main.tf` provisions
  the shared HMAC key, wired to `auth_api` via the `ADMIN_API_CSRF_SECRET_ID`
  environment variable. `admin_api_never_exposes_a_post_route` is kept
  unchanged, per "Defence in depth that stays" above.
- **`node-vlinder-auth`**: mints the `vln_auth_csrf` cookie (session-scoped,
  `HMAC(session-id, csrf-secret)`) and the SPA echoes it in the
  `X-Vln-Csrf-Token` header on every state-changing request.

### A note on rotation

`admin_api_csrf_secret` is rotated on the same 30-day schedule as this
module's other auth secrets (`aws_scheduler_schedule.rotate_admin_api_csrf_secret`),
but its rotation-tolerance story is different from theirs, and deliberately
simpler: nothing ever re-reads `AWSPREVIOUS` for this secret. Verification is
a pure string comparison at the edge that never touches Secrets Manager at
all — it only compares a cookie to a header, both already on the request.
Rotating the secret only changes what key mints *new* `vln_auth_csrf` cookies
going forward; a cookie already issued stays internally self-consistent (its
own value still equals `HMAC(session-id, whichever secret minted it)`) and
keeps matching the header the SPA echoes back, regardless of which secret
version was current when it was minted. There is no "current+previous" fetch
pattern to build here, unlike `auth_session_signing_key` and friends, because
there is no verification step that would ever need one.
