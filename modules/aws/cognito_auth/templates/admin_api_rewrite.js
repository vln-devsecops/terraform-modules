// Viewer-request handler for the /admin/api/* cache behavior.
// Strips the /admin/api prefix so that requests from the admin SPA are
// forwarded to the HTTP API Gateway as root-relative paths.
// Example: GET /admin/api/users -> GET /users on the API Gateway invoke URL
function handler(event) {
  var request = event.request;
  request.uri = request.uri.replace(/^\/admin\/api/, '') || '/';
  return request;
}
