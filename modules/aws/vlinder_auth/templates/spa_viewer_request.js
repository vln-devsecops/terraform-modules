// Viewer-request handler for the auth SPA's S3 default behavior.
// Routes /admin and /admin/* to /admin/index.html (the admin entry point),
// and everything else to /index.html (the login entry point). Paths with
// file extensions pass through unchanged so static assets are served as-is.
function handler(event) {
  var request = event.request;
  var uri = request.uri;

  // /.well-known/* (the OIDC discovery document) is extensionless by
  // specification, so it would otherwise fail the static-asset check below
  // and get silently rewritten to /index.html with a 200 -- a failure that
  // looks like success to every consumer. Let it through unchanged.
  if (uri.startsWith('/.well-known/')) {
    return request;
  }

  // Static asset — let it through unchanged
  var lastSegment = uri.split('/').pop();
  if (lastSegment.includes('.')) {
    return request;
  }

  // Admin routes -> admin entry point
  if (uri === '/admin' || uri.startsWith('/admin/')) {
    request.uri = '/admin/index.html';
    return request;
  }

  // All other extensionless paths (including /) -> login entry point
  request.uri = '/index.html';
  return request;
}
