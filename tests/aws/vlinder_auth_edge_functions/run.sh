#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "${script_dir}/../_lib.sh"

work_dir="$(mktemp -d)"

cleanup() {
  local exit_code="$1"
  rm -rf "${work_dir}"
  run_terraform_cleanup "${script_dir}" "${exit_code}"
}

trap 'cleanup "$?"' EXIT

export TF_VAR_name_suffix="${TF_VAR_name_suffix:-$(random_suffix)}"
export TF_VAR_aws_region="${TF_VAR_aws_region:-$(default_aws_region)}"

terraform_init_apply "${script_dir}"

admin_api_rewrite_name="$(terraform -chdir="${script_dir}" output -raw admin_api_rewrite_function_name)"
spa_viewer_request_name="$(terraform -chdir="${script_dir}" output -raw spa_viewer_request_function_name)"

# --- Live cloudfront-js-2.0 runtime smoke test ------------------------------
#
# terraform apply above only proves the function *object* was accepted by the
# CreateFunction API in DEVELOPMENT stage; CreateFunction does not execute the
# JS. A CloudFront Function that fails to parse (e.g. ES2020+ syntax such as
# `?.`/`??`, which cloudfront-js-2.0 rejects) still creates successfully --
# the failure only shows up when the runtime actually tries to run it, which
# is exactly what happened in production for months before it was
# root-caused with a live `aws cloudfront test-function` call. That call is
# what this section reproduces, against the exact templates/dist/*.js files
# modules/aws/vlinder_auth deploys.

call_test_function() {
  local function_name="$1"
  local event_file="$2"
  local etag

  etag="$(aws cloudfront describe-function \
    --name "${function_name}" \
    --stage DEVELOPMENT \
    --region "${TF_VAR_aws_region}" \
    --query 'ETag' \
    --output text)"

  aws cloudfront test-function \
    --name "${function_name}" \
    --if-match "${etag}" \
    --stage DEVELOPMENT \
    --event-object "fileb://${event_file}" \
    --region "${TF_VAR_aws_region}" \
    --output json
}

# --- admin_api_rewrite event fixtures ---------------------------------------

cat >"${work_dir}/admin_get_with_session.json" <<'JSON'
{
  "version": "1.0",
  "context": { "eventType": "viewer-request" },
  "viewer": { "ip": "1.2.3.4" },
  "request": {
    "method": "GET",
    "uri": "/api/v1/roles",
    "querystring": {},
    "headers": {
      "host": { "value": "example.test" }
    },
    "cookies": {
      "vln_auth_session": { "value": "smoke-test-session-token" }
    }
  }
}
JSON

cat >"${work_dir}/admin_patch_no_csrf.json" <<'JSON'
{
  "version": "1.0",
  "context": { "eventType": "viewer-request" },
  "viewer": { "ip": "1.2.3.4" },
  "request": {
    "method": "PATCH",
    "uri": "/api/v1/roles/123",
    "querystring": {},
    "headers": {
      "host": { "value": "example.test" }
    },
    "cookies": {}
  }
}
JSON

cat >"${work_dir}/admin_patch_with_csrf.json" <<'JSON'
{
  "version": "1.0",
  "context": { "eventType": "viewer-request" },
  "viewer": { "ip": "1.2.3.4" },
  "request": {
    "method": "PATCH",
    "uri": "/api/v1/roles/123",
    "querystring": {},
    "headers": {
      "host": { "value": "example.test" },
      "x-vln-csrf-token": { "value": "smoke-test-csrf-token" }
    },
    "cookies": {
      "vln_auth_csrf": { "value": "smoke-test-csrf-token" }
    }
  }
}
JSON

# --- admin_api_rewrite: GET with a session cookie -> bearer-lifted ----------

call_test_function "${admin_api_rewrite_name}" "${work_dir}/admin_get_with_session.json" \
  >"${work_dir}/admin_get_with_session.result.json"

python3 - "${work_dir}/admin_get_with_session.result.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as fh:
    result = json.load(fh)["TestResult"]

error_message = result.get("FunctionErrorMessage")
assert not error_message, (
    "admin_api_rewrite GET-with-session-cookie case raised a FunctionErrorMessage "
    "-- this means cloudfront-js-2.0 rejected the deployed dist/admin_api_rewrite.js "
    "at runtime (a real syntax/runtime incompatibility, exactly what happened with "
    f"the unguarded `?.` before PR #319/#320): {error_message!r}"
)

output = json.loads(result["FunctionOutput"])
# aws cloudfront test-function wraps whichever kind of object the function
# actually returned: {"request": {...}} for a passthrough/modified request,
# {"response": {...}} for a short-circuit response. It is NOT the flat
# object itself -- confirmed empirically against a live throwaway function.
assert "request" in output, (
    f"expected a session cookie to pass through as a bearer-lifted request, got: {output!r}"
)
payload = output["request"]
auth_header = payload["headers"]["authorization"]["value"]
expected = "Bearer smoke-test-session-token"
assert auth_header == expected, (
    f"expected bearer-lifted Authorization header {expected!r}, got {auth_header!r}"
)
PY

# --- admin_api_rewrite: state-changing method with no CSRF -> 403 -----------

call_test_function "${admin_api_rewrite_name}" "${work_dir}/admin_patch_no_csrf.json" \
  >"${work_dir}/admin_patch_no_csrf.result.json"

python3 - "${work_dir}/admin_patch_no_csrf.result.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as fh:
    result = json.load(fh)["TestResult"]

error_message = result.get("FunctionErrorMessage")
assert not error_message, (
    "admin_api_rewrite PATCH-without-CSRF case raised a FunctionErrorMessage -- "
    "this means cloudfront-js-2.0 rejected the deployed dist/admin_api_rewrite.js "
    "at runtime (a real syntax/runtime incompatibility, exactly what happened with "
    f"the unguarded `?.` before PR #319/#320): {error_message!r}"
)

output = json.loads(result["FunctionOutput"])
assert "response" in output, (
    "expected the double-submit CSRF check to reject with a response object "
    f"(statusCode 403), but got: {output!r}"
)
payload = output["response"]
status_code = payload.get("statusCode")
assert status_code == 403, (
    f"expected the double-submit CSRF check to reject with statusCode 403, got {status_code!r}"
)
PY

# --- admin_api_rewrite: state-changing method with matching CSRF -> passes --

call_test_function "${admin_api_rewrite_name}" "${work_dir}/admin_patch_with_csrf.json" \
  >"${work_dir}/admin_patch_with_csrf.result.json"

python3 - "${work_dir}/admin_patch_with_csrf.result.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as fh:
    result = json.load(fh)["TestResult"]

error_message = result.get("FunctionErrorMessage")
assert not error_message, (
    "admin_api_rewrite PATCH-with-matching-CSRF case raised a FunctionErrorMessage -- "
    "this means cloudfront-js-2.0 rejected the deployed dist/admin_api_rewrite.js at "
    "runtime (a real syntax/runtime incompatibility, exactly what happened with the "
    f"unguarded `?.` before PR #319/#320): {error_message!r}"
)

output = json.loads(result["FunctionOutput"])
assert "request" in output, (
    "expected a matching double-submit CSRF cookie/header to pass through as the "
    f"modified request, but got a rejection response object: {output!r}"
)
payload = output["request"]
assert payload.get("uri") == "/api/v1/roles/123", (
    f"expected the pass-through request's uri to be unchanged, got {payload.get('uri')!r}"
)
PY

# --- spa_viewer_request event fixtures --------------------------------------

cat >"${work_dir}/spa_admin.json" <<'JSON'
{
  "version": "1.0",
  "context": { "eventType": "viewer-request" },
  "viewer": { "ip": "1.2.3.4" },
  "request": {
    "method": "GET",
    "uri": "/admin",
    "querystring": {},
    "headers": {
      "host": { "value": "example.test" }
    },
    "cookies": {}
  }
}
JSON

cat >"${work_dir}/spa_root.json" <<'JSON'
{
  "version": "1.0",
  "context": { "eventType": "viewer-request" },
  "viewer": { "ip": "1.2.3.4" },
  "request": {
    "method": "GET",
    "uri": "/",
    "querystring": {},
    "headers": {
      "host": { "value": "example.test" }
    },
    "cookies": {}
  }
}
JSON

cat >"${work_dir}/spa_asset.json" <<'JSON'
{
  "version": "1.0",
  "context": { "eventType": "viewer-request" },
  "viewer": { "ip": "1.2.3.4" },
  "request": {
    "method": "GET",
    "uri": "/assets/app.js",
    "querystring": {},
    "headers": {
      "host": { "value": "example.test" }
    },
    "cookies": {}
  }
}
JSON

# --- spa_viewer_request: /admin -> /admin/index.html ------------------------

call_test_function "${spa_viewer_request_name}" "${work_dir}/spa_admin.json" \
  >"${work_dir}/spa_admin.result.json"

python3 - "${work_dir}/spa_admin.result.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as fh:
    result = json.load(fh)["TestResult"]

error_message = result.get("FunctionErrorMessage")
assert not error_message, (
    "spa_viewer_request /admin case raised a FunctionErrorMessage -- this means "
    "cloudfront-js-2.0 rejected the deployed dist/spa_viewer_request.js at runtime "
    f"(a real syntax/runtime incompatibility): {error_message!r}"
)

output = json.loads(result["FunctionOutput"])
assert "request" in output, f"expected a passthrough request, got: {output!r}"
payload = output["request"]
assert payload.get("uri") == "/admin/index.html", (
    f"expected /admin to rewrite to /admin/index.html, got {payload.get('uri')!r}"
)
PY

# --- spa_viewer_request: / -> /index.html -----------------------------------

call_test_function "${spa_viewer_request_name}" "${work_dir}/spa_root.json" \
  >"${work_dir}/spa_root.result.json"

python3 - "${work_dir}/spa_root.result.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as fh:
    result = json.load(fh)["TestResult"]

error_message = result.get("FunctionErrorMessage")
assert not error_message, (
    "spa_viewer_request / case raised a FunctionErrorMessage -- this means "
    "cloudfront-js-2.0 rejected the deployed dist/spa_viewer_request.js at runtime "
    f"(a real syntax/runtime incompatibility): {error_message!r}"
)

output = json.loads(result["FunctionOutput"])
assert "request" in output, f"expected a passthrough request, got: {output!r}"
payload = output["request"]
assert payload.get("uri") == "/index.html", (
    f"expected / to rewrite to /index.html, got {payload.get('uri')!r}"
)
PY

# --- spa_viewer_request: static asset passthrough ---------------------------

call_test_function "${spa_viewer_request_name}" "${work_dir}/spa_asset.json" \
  >"${work_dir}/spa_asset.result.json"

python3 - "${work_dir}/spa_asset.result.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as fh:
    result = json.load(fh)["TestResult"]

error_message = result.get("FunctionErrorMessage")
assert not error_message, (
    "spa_viewer_request static-asset case raised a FunctionErrorMessage -- this means "
    "cloudfront-js-2.0 rejected the deployed dist/spa_viewer_request.js at runtime "
    f"(a real syntax/runtime incompatibility): {error_message!r}"
)

output = json.loads(result["FunctionOutput"])
assert "request" in output, f"expected a passthrough request, got: {output!r}"
payload = output["request"]
assert payload.get("uri") == "/assets/app.js", (
    f"expected a static asset uri to pass through unchanged, got {payload.get('uri')!r}"
)
PY

printf 'All cloudfront-js-2.0 live runtime smoke assertions passed.\n'
