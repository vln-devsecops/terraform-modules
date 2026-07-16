#!/usr/bin/env bash
#
# Real HTTP round-trip for the aws/lambda module's cors variable: apply a
# public Function URL with cors set, then hit it over the network and assert
# on the actual Access-Control-* response headers AWS returns - not just
# what Terraform planned to configure. terraform test (see
# modules/aws/lambda/tests/basic.tftest.hcl) already covers the plan-time
# shape of the cors block; this fixture is the thing that would have caught
# it if AWS's real behavior didn't match that shape.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "${script_dir}/../../_lib.sh"

cleanup() {
  local exit_code="$1"
  run_terraform_cleanup "${script_dir}" "${exit_code}"
}

trap 'cleanup "$?"' EXIT

export TF_VAR_name_suffix="${TF_VAR_name_suffix:-$(random_suffix)}"
export TF_VAR_aws_region="${TF_VAR_aws_region:-$(default_aws_region)}"
allowed_origin="https://example.com"
export TF_VAR_allowed_origin="${allowed_origin}"

terraform_init_apply "${script_dir}"

url="$(terraform -chdir="${script_dir}" output -raw url)"

[[ "${url}" == https://* ]] || {
  printf 'expected a Lambda Function URL, got %s\n' "${url}" >&2
  exit 1
}

# Function URLs can take a few seconds to become invokable right after
# creation - retry instead of asserting immediately on a possible 5xx.
curl_with_retry() {
  local attempt
  local response
  for attempt in $(seq 1 10); do
    if response="$(curl -sS -D - -o /tmp/cors-probe-body "$@" 2>/tmp/cors-probe-curl-err)"; then
      printf '%s' "${response}"
      return 0
    fi
    sleep 3
  done
  printf 'curl failed after 10 attempts: %s\n' "$(cat /tmp/cors-probe-curl-err)" >&2
  return 1
}

# Given a Function URL configured with cors.allow_origins = [allowed_origin],
# when a browser sends a CORS preflight OPTIONS request for that origin,
# then AWS must answer with matching Access-Control-* headers - and it must
# do so without invoking the function at all (this is the whole point of
# native Function URL CORS over hand-coded handler CORS).
# curl -D emits headers with CRLF line endings; strip the \r so plain grep
# anchors work (grep's BRE has no portable escape for a literal CR byte -
# leaving \r in the pattern instead of the text silently never matches).
preflight_headers="$(curl_with_retry -X OPTIONS "${url}" \
  -H "Origin: ${allowed_origin}" \
  -H "Access-Control-Request-Method: POST" | tr -d '\r')"

echo "${preflight_headers}" | grep -qi '^access-control-allow-origin: '"${allowed_origin//./\\.}"'$' || {
  printf 'expected Access-Control-Allow-Origin: %s in preflight response, got:\n%s\n' "${allowed_origin}" "${preflight_headers}" >&2
  exit 1
}

echo "${preflight_headers}" | grep -qi '^access-control-allow-methods:.*POST' || {
  printf 'expected Access-Control-Allow-Methods to include POST in preflight response, got:\n%s\n' "${preflight_headers}" >&2
  exit 1
}

# Given the same configuration, when a real (non-preflight) GET request is
# made, then the Access-Control-Allow-Origin header must still be present on
# the actual invocation response, not just on OPTIONS - AWS documents CORS
# headers as applying to every response, and this is the behavior consumers
# (like node-dashboard's browser-side fetch) actually depend on.
get_headers="$(curl_with_retry -X GET "${url}" -H "Origin: ${allowed_origin}" | tr -d '\r')"

echo "${get_headers}" | grep -qi '^access-control-allow-origin: '"${allowed_origin//./\\.}"'$' || {
  printf 'expected Access-Control-Allow-Origin: %s on a real GET response, got:\n%s\n' "${allowed_origin}" "${get_headers}" >&2
  exit 1
}

http_status="$(echo "${get_headers}" | head -1 | grep -o '[0-9][0-9][0-9]')"
[[ "${http_status}" == "200" ]] || {
  printf 'expected a 200 response from the (echo-fallback) Lambda, got status %s\n' "${http_status}" >&2
  exit 1
}

printf 'cors_function_url round-trip: OPTIONS preflight and real GET both carried the expected CORS headers.\n'
