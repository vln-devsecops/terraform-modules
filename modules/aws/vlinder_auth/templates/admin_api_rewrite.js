// Viewer-request handler for the /api/v1/* cache behavior. Passes the URI
// through unmodified -- the API Gateway route_key already carries /api/v1
// (nothing strips it in transit), so a future /api/v2 can be routed
// alongside without touching this function. The /api/v1/auth* behavior is
// matched first (higher precedence), so auth requests never reach here.
//
// No optional-chaining operator anywhere in this file, despite runtime =
// "cloudfront-js-2.0" below: confirmed via `aws cloudfront test-function`
// against the actual deployed function that this runtime's parser rejects
// that operator with a SyntaxError, and CloudFront then serves a generic
// 503 HTML error page for every single request through this behavior,
// never reaching the origin at all -- exactly the silent,
// 100%-reproducible admin-panel failure this file's plain `a && a.b` style
// (instead of that operator) is now guarding against. See this module's
// own admin_api_rewrite_avoids_syntax_cloudfront_js_2_0_rejects test.
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
// automatically). Three things keep that safe and MUST hold:
//   1. vln_auth_session must be issued SameSite=Strict by the auth Lambda
//      (see session.ts's serializeSessionCookie), so it isn't sent on a
//      cross-site navigation/form-submission in the first place.
//   2. The admin API must never expose a POST route (see
//      admin_api_never_exposes_a_post_route in tests/admin_api.tftest.hcl) --
//      PATCH/PUT/DELETE aren't form-submittable, so even a same-site-cookie
//      CSRF vector has no route to land on. This stays as defence in depth
//      even with (3) below in place.
//   3. Double-submit CSRF protection, always on: a second, non-HttpOnly
//      cookie (vln_auth_csrf, HMAC(session-id, csrf-secret) -- minted by
//      auth_api in node-vlinder-auth) must be echoed back by the SPA in the
//      X-Vln-Csrf-Token header on every state-changing request. This
//      function is where that gets verified -- a plain string comparison,
//      well within a CloudFront Function's tiny compute budget and lack of
//      a crypto library -- and it rejects (403) before the Bearer lift below
//      runs for any request that fails it. See doc/admin-api-csrf.md for the
//      full posture.
//
// Also note: if the cookie is present, this silently overrides any
// client-supplied Authorization header -- the SPA can't accidentally
// authenticate as a different principal than its own session by sending one.
function handler(event) {
  const request = event.request;

  // CloudFront's own origin custom_header (added later, at origin-request
  // time) overwrites a same-named viewer header before forwarding to
  // origin -- but drop any client-supplied copy here too, at the edge,
  // rather than relying solely on that. The admin API's Lambda authorizer
  // rejects any request without the correct value, so this is what closes
  // off direct execute-api access bypassing CloudFront.
  delete request.headers['x-origin-verify'];

  const cookies = request.cookies || {};

  // Double-submit CSRF check, always on -- not deferred until a
  // form-submittable route exists (see doc/admin-api-csrf.md). Only
  // state-changing methods are in scope: GET/HEAD/OPTIONS can't carry a
  // form-submitted cross-site request that mutates state. Short-circuit
  // with a 403 response object (not a request) before any Bearer-lift work
  // below, since there's no point authenticating a request about to be
  // rejected anyway.
  const method = request.method;
  if (method !== 'GET' && method !== 'HEAD' && method !== 'OPTIONS') {
    const csrfCookie = cookies['vln_auth_csrf'] && cookies['vln_auth_csrf'].value;
    const csrfHeader = request.headers['x-vln-csrf-token'] && request.headers['x-vln-csrf-token'].value;

    if (!csrfCookie || !csrfHeader || csrfCookie !== csrfHeader) {
      return {
        statusCode: 403,
        statusDescription: 'Forbidden',
        headers: {
          'content-type': { value: 'application/json' },
        },
        body: {
          encoding: 'text',
          data: '{"error":"csrf_validation_failed"}',
        },
      };
    }
  }

  if (cookies['vln_auth_session'] && cookies['vln_auth_session'].value) {
    request.headers['authorization'] = { value: 'Bearer ' + cookies['vln_auth_session'].value };
  }

  return request;
}
