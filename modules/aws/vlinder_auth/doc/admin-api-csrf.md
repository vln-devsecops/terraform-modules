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
exactly the mechanism CSRF exploits).

## The posture: double-submit, unconditionally

The admin API carries **double-submit CSRF protection, always on** — not
deferred until a form-submittable route appears.

This is a change from the earlier position, which was to rely on `SameSite`
plus an enforced no-`POST`-routes invariant and build double-submit only when
something actually needed it. That reasoning was sound while the exposure was
conditional and the admin API was the only cookie-authenticated surface in the
system. It stopped being sound once cookie-only became the default token
delivery for every consuming application's BFF (see `node-vlinder-auth`'s
`doc/rationale.md`): cookie authentication is now the normal case across the
whole system, so it gets one posture, implemented once, reviewed once, rather
than a strong default in one place and a conditional exception here.

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

Not yet implemented — this documents the agreed design, and the work is
tracked as step 8a of `node-vlinder-auth`'s `doc/plan.md`, sequenced after the
reference BFF establishes the scheme both surfaces share.
