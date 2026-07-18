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
function handler(event) {
  var request = event.request;
  request.uri = request.uri.replace(/^\/api\/v1/, '') || '/';

  var cookies = request.cookies || {};
  if (cookies['vln_auth_session'] && cookies['vln_auth_session'].value) {
    request.headers['authorization'] = { value: 'Bearer ' + cookies['vln_auth_session'].value };
  }

  return request;
}
