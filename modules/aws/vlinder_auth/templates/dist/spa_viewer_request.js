// GENERATED FILE -- do not edit directly.
// Source: ../src/spa_viewer_request.js -- regenerate via `npm run build` in edge-functions-build/.
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  if (uri.startsWith("/.well-known/")) {
    return request;
  }
  var lastSegment = uri.split("/").pop();
  if (lastSegment.includes(".")) {
    return request;
  }
  if (uri === "/admin" || uri.startsWith("/admin/")) {
    request.uri = "/admin/index.html";
    return request;
  }
  request.uri = "/index.html";
  return request;
}
