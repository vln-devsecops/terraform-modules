// Viewer-request handler for the /api/v1/* cache behavior.
// Strips the /api/v1 prefix so that requests from the admin SPA are
// forwarded to the HTTP API Gateway as root-relative REST paths.
// Example: GET /api/v1/users -> GET /users on the API Gateway invoke URL.
// The /api/v1/idp* behavior is matched first (higher precedence), so IDP
// requests never reach here.
function handler(event) {
  var request = event.request;
  request.uri = request.uri.replace(/^\/api\/v1/, '') || '/';
  return request;
}
