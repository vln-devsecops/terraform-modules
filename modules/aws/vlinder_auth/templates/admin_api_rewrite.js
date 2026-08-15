// Viewer-request handler for the /api/v1/* cache behavior.
// Strips the /api/v1 prefix so that requests from the admin SPA are
// forwarded to the HTTP API Gateway as root-relative REST paths.
// Example: GET /api/v1/users -> GET /users on the API Gateway invoke URL.
// The /api/v1/auth* behavior is matched first (higher precedence), so auth
// requests never reach here.
//
// The admin API's JWT authorizer reads the Authorization header, but the SPA
// holds its session as an HttpOnly cookie (JS can't set the header). Lift the
// cookie into a Bearer Authorization header at the edge so the authorizer works
// unchanged. CloudFront Functions see all viewer cookies regardless of the
// behavior's cookie-forwarding config.
//
// This turns the admin API from bearer-token semantics (CSRF-immune -- a
// cross-site page can't set a custom header on a form submission) into
// cookie semantics (CSRF-relevant -- the browser attaches the cookie
// automatically). Two invariants keep that safe and MUST hold:
//   1. vln_auth_session must be issued SameSite=Strict or Lax by the auth
//      Lambda (see session.ts's serializeSessionCookie), so it isn't sent on
//      a cross-site navigation/form-submission in the first place.
//   2. The admin API must never expose a POST route (see
//      admin_api_never_exposes_a_post_route in tests/admin_api.tftest.hcl) --
//      PATCH/PUT/DELETE aren't form-submittable, so even a same-site-cookie
//      CSRF vector has no route to land on.
// If a form-submittable admin route is ever added, this lift needs a real
// CSRF defense (e.g. a double-submit token) before it ships -- see
// doc/admin-api-csrf.md for the full posture and the double-submit design.
//
// Also note: if the cookie is present, this silently overrides any
// client-supplied Authorization header -- the SPA can't accidentally
// authenticate as a different principal than its own session by sending one.
function handler(event) {
  var request = event.request;
  request.uri = request.uri.replace(/^\/api\/v1/, '') || '/';

  var cookies = request.cookies || {};
  if (cookies['vln_auth_session'] && cookies['vln_auth_session'].value) {
    request.headers['authorization'] = { value: 'Bearer ' + cookies['vln_auth_session'].value };
  }

  return request;
}
