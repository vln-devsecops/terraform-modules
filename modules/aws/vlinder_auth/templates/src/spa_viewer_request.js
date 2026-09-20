// Viewer-request handler for the auth SPA's S3 default behavior.
// Routes /admin and /admin/* to /admin/index.html (the admin entry point),
// and everything else to /index.html (the login entry point). Paths with
// file extensions pass through unchanged so static assets are served as-is.
//
// This is SOURCE, not what Terraform deploys: see the header comment in
// admin_api_rewrite.js in this same directory for the templates/src ->
// templates/dist build pipeline. This file never needed modernizing (no
// syntax cloudfront-js-2.0 rejects), so its plain ES5-ish `var` style is
// left alone rather than churned for its own sake.
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
