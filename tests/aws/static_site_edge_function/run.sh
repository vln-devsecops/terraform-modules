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

both_enabled_name="$(terraform -chdir="${script_dir}" output -json viewer_request_function_names | python3 -c 'import json,sys; print(json.load(sys.stdin)["both_enabled"])')"
both_disabled_name="$(terraform -chdir="${script_dir}" output -json viewer_request_function_names | python3 -c 'import json,sys; print(json.load(sys.stdin)["both_disabled"])')"

# --- Live cloudfront-js-2.0 runtime smoke test ------------------------------
#
# terraform apply above only proves the function *object* was accepted by the
# CreateFunction API in DEVELOPMENT stage; CreateFunction does not execute the
# JS. modules/aws/static_site/templates/viewer_request.js.tftpl is currently
# plain ES5.1-style code with no known runtime incompatibility, but
# tests/aws/vlinder_auth_edge_functions/ proved that a cloudfront-js-2.0
# rejection (e.g. ES2020+ syntax such as `?.`/`??`) creates successfully and
# only fails once the runtime actually tries to run it -- something
# `terraform test`'s mock provider can never catch. This section reproduces
# that live `aws cloudfront test-function` call against both rendered
# variants of the real templatefile() output, pre-emptively closing the same
# blind spot here.

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

# Fixture credentials rendered into the both_enabled function's basic-auth
# header comparison -- must match main.tf's edge_function_variants.both_enabled.
basic_auth_correct_header="Basic $(printf '%s' 'smoketest:smoke-test-password' | base64 -w0)"

# --- both_enabled event fixtures --------------------------------------------

cat >"${work_dir}/enabled_no_auth.json" <<'JSON'
{
  "version": "1.0",
  "context": { "eventType": "viewer-request" },
  "viewer": { "ip": "1.2.3.4" },
  "request": {
    "method": "GET",
    "uri": "/docs/",
    "querystring": {},
    "headers": {
      "host": { "value": "example.test" }
    },
    "cookies": {}
  }
}
JSON

python3 - "${work_dir}/enabled_auth_docs_slash.json" "${basic_auth_correct_header}" <<'PY'
import json
import sys

out_path, auth_header = sys.argv[1], sys.argv[2]

event = {
    "version": "1.0",
    "context": {"eventType": "viewer-request"},
    "viewer": {"ip": "1.2.3.4"},
    "request": {
        "method": "GET",
        "uri": "/docs/",
        "querystring": {},
        "headers": {
            "host": {"value": "example.test"},
            "authorization": {"value": auth_header},
        },
        "cookies": {},
    },
}

with open(out_path, "w") as fh:
    json.dump(event, fh)
PY

python3 - "${work_dir}/enabled_auth_about.json" "${basic_auth_correct_header}" <<'PY'
import json
import sys

out_path, auth_header = sys.argv[1], sys.argv[2]

event = {
    "version": "1.0",
    "context": {"eventType": "viewer-request"},
    "viewer": {"ip": "1.2.3.4"},
    "request": {
        "method": "GET",
        "uri": "/about",
        "querystring": {},
        "headers": {
            "host": {"value": "example.test"},
            "authorization": {"value": auth_header},
        },
        "cookies": {},
    },
}

with open(out_path, "w") as fh:
    json.dump(event, fh)
PY

python3 - "${work_dir}/enabled_auth_healthz.json" "${basic_auth_correct_header}" <<'PY'
import json
import sys

out_path, auth_header = sys.argv[1], sys.argv[2]

event = {
    "version": "1.0",
    "context": {"eventType": "viewer-request"},
    "viewer": {"ip": "1.2.3.4"},
    "request": {
        "method": "GET",
        "uri": "/healthz",
        "querystring": {},
        "headers": {
            "host": {"value": "example.test"},
            "authorization": {"value": auth_header},
        },
        "cookies": {},
    },
}

with open(out_path, "w") as fh:
    json.dump(event, fh)
PY

# --- both_enabled: no Authorization header -> 401 ---------------------------

call_test_function "${both_enabled_name}" "${work_dir}/enabled_no_auth.json" \
  >"${work_dir}/enabled_no_auth.result.json"

python3 - "${work_dir}/enabled_no_auth.result.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as fh:
    result = json.load(fh)["TestResult"]

error_message = result.get("FunctionErrorMessage")
assert not error_message, (
    "both_enabled no-Authorization-header case raised a FunctionErrorMessage -- "
    "this means cloudfront-js-2.0 rejected the rendered viewer_request.js.tftpl "
    f"output at runtime (a real syntax/runtime incompatibility): {error_message!r}"
)

output = json.loads(result["FunctionOutput"])
# aws cloudfront test-function wraps whichever kind of object the function
# actually returned: {"request": {...}} for a passthrough/modified request,
# {"response": {...}} for a short-circuit response (e.g. this 401). It is
# NOT the flat object itself -- confirmed empirically against a live
# throwaway function, since this is undocumented enough to have been wrong
# here on the first attempt.
assert "response" in output, (
    "expected a missing Authorization header to short-circuit with a response "
    f"object (statusCode 401), but got: {output!r}"
)
payload = output["response"]
assert payload.get("statusCode") == 401, (
    f"expected a missing Authorization header to be rejected with statusCode 401, "
    f"got {payload.get('statusCode')!r}"
)

challenge = payload["headers"]["www-authenticate"]["value"]
assert "Smoke Test" in challenge, (
    f"expected the www-authenticate challenge to contain the configured realm "
    f"'Smoke Test', got {challenge!r}"
)
PY

# --- both_enabled: correct auth + trailing-slash uri -> rewritten + passed --

call_test_function "${both_enabled_name}" "${work_dir}/enabled_auth_docs_slash.json" \
  >"${work_dir}/enabled_auth_docs_slash.result.json"

python3 - "${work_dir}/enabled_auth_docs_slash.result.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as fh:
    result = json.load(fh)["TestResult"]

error_message = result.get("FunctionErrorMessage")
assert not error_message, (
    "both_enabled correct-auth /docs/ case raised a FunctionErrorMessage -- this "
    "means cloudfront-js-2.0 rejected the rendered viewer_request.js.tftpl output "
    f"at runtime (a real syntax/runtime incompatibility): {error_message!r}"
)

output = json.loads(result["FunctionOutput"])
assert "request" in output, (
    "expected a correct Authorization header to pass the basic-auth check and "
    f"return the modified request, but got: {output!r}"
)
payload = output["request"]
assert payload.get("uri") == "/docs/index.html", (
    f"expected /docs/ to rewrite to /docs/index.html, got {payload.get('uri')!r}"
)
PY

# --- both_enabled: correct auth + extensionless uri -> rewritten -----------

call_test_function "${both_enabled_name}" "${work_dir}/enabled_auth_about.json" \
  >"${work_dir}/enabled_auth_about.result.json"

python3 - "${work_dir}/enabled_auth_about.result.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as fh:
    result = json.load(fh)["TestResult"]

error_message = result.get("FunctionErrorMessage")
assert not error_message, (
    "both_enabled correct-auth /about case raised a FunctionErrorMessage -- this "
    "means cloudfront-js-2.0 rejected the rendered viewer_request.js.tftpl output "
    f"at runtime (a real syntax/runtime incompatibility): {error_message!r}"
)

output = json.loads(result["FunctionOutput"])
assert "request" in output, (
    f"expected a correct Authorization header to pass through as a request, got: {output!r}"
)
payload = output["request"]
assert payload.get("uri") == "/about/index.html", (
    f"expected extensionless /about to rewrite to /about/index.html, got {payload.get('uri')!r}"
)
PY

# --- both_enabled: correct auth + excepted uri -> unchanged -----------------

call_test_function "${both_enabled_name}" "${work_dir}/enabled_auth_healthz.json" \
  >"${work_dir}/enabled_auth_healthz.result.json"

python3 - "${work_dir}/enabled_auth_healthz.result.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as fh:
    result = json.load(fh)["TestResult"]

error_message = result.get("FunctionErrorMessage")
assert not error_message, (
    "both_enabled correct-auth /healthz case raised a FunctionErrorMessage -- this "
    "means cloudfront-js-2.0 rejected the rendered viewer_request.js.tftpl output "
    f"at runtime (a real syntax/runtime incompatibility): {error_message!r}"
)

output = json.loads(result["FunctionOutput"])
assert "request" in output, (
    f"expected a correct Authorization header to pass through as a request, got: {output!r}"
)
payload = output["request"]
assert payload.get("uri") == "/healthz", (
    "expected /healthz, which is in pretty_url_exceptions, to pass through "
    f"unchanged despite being extensionless, got {payload.get('uri')!r}"
)
PY

# --- both_disabled event fixtures -------------------------------------------

cat >"${work_dir}/disabled_no_auth.json" <<'JSON'
{
  "version": "1.0",
  "context": { "eventType": "viewer-request" },
  "viewer": { "ip": "1.2.3.4" },
  "request": {
    "method": "GET",
    "uri": "/dashboard/data",
    "querystring": {},
    "headers": {
      "host": { "value": "example.test" }
    },
    "cookies": {}
  }
}
JSON

cat >"${work_dir}/disabled_about.json" <<'JSON'
{
  "version": "1.0",
  "context": { "eventType": "viewer-request" },
  "viewer": { "ip": "1.2.3.4" },
  "request": {
    "method": "GET",
    "uri": "/about",
    "querystring": {},
    "headers": {
      "host": { "value": "example.test" }
    },
    "cookies": {}
  }
}
JSON

# --- both_disabled: no Authorization header -> unchanged request -----------

call_test_function "${both_disabled_name}" "${work_dir}/disabled_no_auth.json" \
  >"${work_dir}/disabled_no_auth.result.json"

python3 - "${work_dir}/disabled_no_auth.result.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as fh:
    result = json.load(fh)["TestResult"]

error_message = result.get("FunctionErrorMessage")
assert not error_message, (
    "both_disabled no-Authorization-header case raised a FunctionErrorMessage -- "
    "this means cloudfront-js-2.0 rejected the rendered viewer_request.js.tftpl "
    f"output at runtime (a real syntax/runtime incompatibility): {error_message!r}"
)

output = json.loads(result["FunctionOutput"])
assert "request" in output, (
    "expected basic auth to be genuinely off (no Authorization header enforced), "
    f"but got a rejection response object: {output!r}"
)
payload = output["request"]
assert payload.get("uri") == "/dashboard/data", (
    f"expected the request uri to pass through unchanged, got {payload.get('uri')!r}"
)
PY

# --- both_disabled: extensionless uri -> unchanged (pretty urls off) -------

call_test_function "${both_disabled_name}" "${work_dir}/disabled_about.json" \
  >"${work_dir}/disabled_about.result.json"

python3 - "${work_dir}/disabled_about.result.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as fh:
    result = json.load(fh)["TestResult"]

error_message = result.get("FunctionErrorMessage")
assert not error_message, (
    "both_disabled extensionless-uri case raised a FunctionErrorMessage -- this "
    "means cloudfront-js-2.0 rejected the rendered viewer_request.js.tftpl output "
    f"at runtime (a real syntax/runtime incompatibility): {error_message!r}"
)

output = json.loads(result["FunctionOutput"])
assert "request" in output, (
    f"expected pretty-url rewriting to be genuinely off and pass through as a "
    f"request, but got: {output!r}"
)
payload = output["request"]
assert payload.get("uri") == "/about", (
    "expected pretty-url rewriting to be genuinely off, leaving an extensionless "
    f"uri unchanged, got {payload.get('uri')!r}"
)
PY

printf 'All cloudfront-js-2.0 live runtime smoke assertions passed.\n'
