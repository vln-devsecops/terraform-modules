// Viewer-request handler for the /api/v1/auth* cache behavior.
// Strips the /api/v1 prefix so requests from the login SPA reach the auth HTTP
// API Gateway as /auth/* routes.
// Example: POST /api/v1/auth/identify -> POST /auth/identify on the API Gateway.
// This behavior is ordered before /api/v1/* so auth requests never fall through
// to the admin API.
function handler(event) {
  var request = event.request;
  request.uri = request.uri.replace(/^\/api\/v1/, '') || '/';
  return request;
}
