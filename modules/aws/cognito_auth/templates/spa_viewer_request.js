// Viewer-request handler for the auth SPA's S3 default behavior.
// Rewrites extensionless paths (SPA client-side routes) to /index.html so
// React Router can handle them; paths with file extensions pass through
// unchanged so static assets (JS, CSS, images) are served as-is.
function handler(event) {
  var request = event.request;
  var uri = request.uri;

  if (uri === '/' || uri === '') {
    request.uri = '/index.html';
    return request;
  }

  // Paths that end with '/' are directory requests: serve index.html
  if (uri.endsWith('/')) {
    request.uri = uri + 'index.html';
    return request;
  }

  // Paths without a file extension are SPA routes: rewrite to index.html
  var lastSegment = uri.split('/').pop();
  if (!lastSegment.includes('.')) {
    request.uri = '/index.html';
  }

  return request;
}
