// Viewer-request handler for the /idp/* cache behavior.
// Strips the /idp prefix so that requests to /idp (and any sub-path) are
// forwarded to Cognito's regional IDP API as root-relative paths.
// Example: POST /idp -> POST / on cognito-idp.<region>.amazonaws.com
function handler(event) {
  var request = event.request;
  request.uri = request.uri.replace(/^\/idp/, '') || '/';
  return request;
}
