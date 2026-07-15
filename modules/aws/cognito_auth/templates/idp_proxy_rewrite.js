// Viewer-request handler for the /api/v1/idp* cache behavior.
// Strips the /api/v1/idp prefix so that requests to it (and any sub-path)
// are forwarded to Cognito's regional IDP API as root-relative paths.
// Example: POST /api/v1/idp -> POST / on cognito-idp.<region>.amazonaws.com
//
// Also re-sets X-Amz-Target explicitly. CloudFront's forwarded_values
// (and origin-request-policy) header allowlisting rejects any header name
// starting with "X-Amz-" at distribution-config time -- it can never be
// listed there, full stop, confirmed against AWS's own documented origin
// custom-header denylist. Cognito's IDP API is a JSON-RPC-style API that
// routes purely on this header (InitiateAuth, SignUp, etc.), so it can't
// just be dropped. CloudFront Functions are a separate mechanism from that
// allowlist and aren't subject to the same restriction (only X-Amz-Cf-*
// and specific X-Amzn-* internal headers are off-limits to functions) --
// viewer-request functions see the full raw request regardless of the
// distribution's header-forwarding config, so the incoming value is read
// here and re-set explicitly, bypassing the allowlist entirely.
function handler(event) {
  var request = event.request;
  request.uri = request.uri.replace(/^\/api\/v1\/idp/, '') || '/';

  var target = request.headers['x-amz-target'];
  if (target && target.value) {
    request.headers['x-amz-target'] = { value: target.value };
  }

  return request;
}
