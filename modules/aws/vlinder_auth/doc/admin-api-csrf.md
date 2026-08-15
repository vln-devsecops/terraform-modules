# Admin API CSRF posture

## Why this exists

`templates/admin_api_rewrite.js` (the CloudFront viewer-request function on
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
exactly the mechanism CSRF exploits). This document is the writeup promised
in that file's comments: how the current state stays safe, the invariant that
keeps it that way, and what to build if the invariant ever needs to be
relaxed.

## Why it's safe today

Two independent layers, either of which is currently sufficient on its own:

1. **`SameSite=Strict`.** `vln_auth_session` is issued with `SameSite=Strict`
   (see `session.ts`'s `serializeSessionCookie` in `node-vlinder-auth`).
   Strict cookies are not attached to *any* cross-site request — including a
   `<form>` POST from an attacker-controlled page — so the browser simply
   never sends the cookie in the CSRF scenario. This is the primary defense.
2. **No form-submittable admin route.** Every route behind `/api/v1/*` is
   `GET`, `PATCH`, `PUT`, or `DELETE` (see `local.admin_api_routes` in
   `main.tf`) — none of which an HTML `<form>` can issue, and a cross-origin
   `fetch` would need CORS the admin API doesn't grant. So even if `SameSite`
   enforcement failed (a browser that predates `SameSite` support, or a bug),
   there is still no request shape a victim's browser could be tricked into
   sending that would land on a state-changing route.

Because both layers would have to fail *at the same time* — `SameSite`
enforcement lapsing **and** a form-submittable route existing — the current
exposure is low. Layer 2 is enforced mechanically: the
`admin_api_never_exposes_a_post_route` run block in
`tests/admin_api.tftest.hcl` asserts against `local.admin_api_routes` (the
actual route-key source of truth that creates the API Gateway routes, not
just the Lambda's downstream `routeKey` switch) that no route uses `POST`.
Adding one fails `terraform test` until the assertion is deliberately
addressed.

### Two things worth knowing, not currently issues

- The cookie lift **silently overrides** any client-supplied `Authorization`
  header when the cookie is present. This is intentional (the SPA can't
  accidentally authenticate as a different principal than its own session)
  but is easy to forget when debugging a request that "ignores" a header you
  set by hand.
- The `startswith(route.route_key, "POST ")` check only catches routes
  declared literally as `"POST ..."`. A future catch-all route (e.g. an
  `"ANY /{proxy+}"` pattern) would implicitly permit POST without ever
  matching that string, silently defeating the assertion. Nothing in this
  module uses catch-all routes today; if that pattern is ever introduced,
  this check needs to be revisited alongside it.

## If a POST (or other form-submittable) route is ever needed

Do not add one without adding CSRF protection at the same time — `SameSite`
alone is not considered sufficient once a form-submittable route exists,
since it depends on every current and future browser enforcing it correctly.
The standard mitigation is a **double-submit CSRF token**, and it fits
naturally into the pieces already in place:

1. **Issue a second, JS-readable cookie** alongside `vln_auth_session` — e.g.
   `vln_auth_csrf`, **not** `HttpOnly`, still `Secure` + `SameSite=Strict`.
   Simplest form: a random value generated when the AS session is created.
   Stronger form: `HMAC(session-id, csrf-secret)`, so the token is bound to
   the session and can't be forged by anyone who can merely set a cookie on
   the origin (matters more with subdomain cookie-tossing risk than it does
   here with a single origin, but cheap to do right from the start).
2. **The SPA echoes it back as a custom header** (e.g. `X-Vln-Csrf-Token`) on
   every state-changing request. A `<form>` can't set custom headers and
   can't read a cookie value into JS to forge one, so this closes the gap a
   form submission would otherwise exploit.
3. **Verify at the edge, in `admin_api_rewrite.js`.** That function already
   inspects `request.cookies` and `request.headers` before performing the
   Bearer lift, so it's the natural place to also reject (`403`) any
   state-changing request where the header is missing or doesn't match the
   `vln_auth_csrf` cookie — CloudFront Functions support only simple,
   synchronous logic, and a string comparison is well within that budget (no
   need to call out for an HMAC recompute if the plain-random-value form is
   used).
4. **Update `admin_api_never_exposes_a_post_route`** (or replace it with an
   assertion appropriate to the new shape) so the test suite reflects the new
   invariant instead of just deleting the guard.

This is intentionally not built now — there is no caller for it, and
speculative CSRF-defense code with nothing exercising it is itself a
liability (untested paths in security-relevant code rot fastest). Build it
when the first form-submittable admin route is actually needed, using this
document as the design.
