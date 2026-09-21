// GENERATED FILE -- do not edit directly.
// Source: ../src/admin_api_rewrite.js -- regenerate via `npm run build` in edge-functions-build/.
function handler(event) {
  var _a, _b, _c;
  const request = event.request;
  delete request.headers["x-origin-verify"];
  const cookies = request.cookies || {};
  const method = request.method;
  if (method !== "GET" && method !== "HEAD" && method !== "OPTIONS") {
    const csrfCookie = (_a = cookies["vln_auth_csrf"]) == null ? void 0 : _a.value;
    const csrfHeader = (_b = request.headers["x-vln-csrf-token"]) == null ? void 0 : _b.value;
    if (!csrfCookie || !csrfHeader || csrfCookie !== csrfHeader) {
      return {
        statusCode: 403,
        statusDescription: "Forbidden",
        headers: {
          "content-type": { value: "application/json" }
        },
        body: {
          encoding: "text",
          data: '{"error":"csrf_validation_failed"}'
        }
      };
    }
  }
  if ((_c = cookies["vln_auth_session"]) == null ? void 0 : _c.value) {
    request.headers["authorization"] = { value: "Bearer " + cookies["vln_auth_session"].value };
  }
  return request;
}
