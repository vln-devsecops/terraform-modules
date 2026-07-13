#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "${script_dir}/../_lib.sh"

cleanup() {
  local exit_code="$1"
  run_terraform_cleanup "${script_dir}" "${exit_code}"
}

trap 'cleanup "$?"' EXIT

base_domain="${COGNITO_AUTH_TEST_BASE_DOMAIN:-${MAIL_TEST_BASE_DOMAIN:-}}"
route53_zone_id="${COGNITO_AUTH_TEST_ROUTE53_ZONE_ID:-${MAIL_TEST_ROUTE53_ZONE_ID:-}}"

require_env AWS_ACCESS_KEY_ID "AWS_ACCESS_KEY_ID must be set to run the cognito_auth live suite."
require_env AWS_SECRET_ACCESS_KEY "AWS_SECRET_ACCESS_KEY must be set to run the cognito_auth live suite."

if [ -z "${base_domain}" ] || [ -z "${route53_zone_id}" ]; then
  printf '%s\n' "Set COGNITO_AUTH_TEST_BASE_DOMAIN and COGNITO_AUTH_TEST_ROUTE53_ZONE_ID (or reuse MAIL_TEST_BASE_DOMAIN and MAIL_TEST_ROUTE53_ZONE_ID) to run the cognito_auth live suite." >&2
  exit 2
fi

export TF_VAR_name_suffix="${TF_VAR_name_suffix:-$(random_suffix)}"
export TF_VAR_aws_region="${TF_VAR_aws_region:-$(default_aws_region)}"
export TF_VAR_base_domain="${TF_VAR_base_domain:-${base_domain}}"
export TF_VAR_route53_zone_id="${TF_VAR_route53_zone_id:-${route53_zone_id}}"

terraform_init_apply "${script_dir}"

user_pool_id="$(terraform -chdir="${script_dir}" output -raw user_pool_id)"
auth_domain="$(terraform -chdir="${script_dir}" output -raw auth_domain)"
admin_panel_url="$(terraform -chdir="${script_dir}" output -raw admin_panel_url)"
admin_api_invoke_url="$(terraform -chdir="${script_dir}" output -raw admin_api_invoke_url)"

aws cognito-idp describe-user-pool --user-pool-id "${user_pool_id}" >/dev/null

python3 - "${admin_panel_url}" "${admin_api_invoke_url}" "${auth_domain}" <<'PY'
import sys

admin_panel_url, admin_api_invoke_url, auth_domain = sys.argv[1], sys.argv[2], sys.argv[3]
assert admin_panel_url.startswith("https://"), f"unexpected admin_panel_url: {admin_panel_url!r}"
assert admin_api_invoke_url.startswith("https://"), f"unexpected admin_api_invoke_url: {admin_api_invoke_url!r}"
assert auth_domain, f"auth_domain output is empty"
PY

record_payload="$(aws route53 list-resource-record-sets \
  --hosted-zone-id "${TF_VAR_route53_zone_id}" \
  --output json)"
python3 - "${record_payload}" "${auth_domain}." <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
auth_domain = sys.argv[2]
records = payload["ResourceRecordSets"]

expected_types = {"A", "AAAA"}
found = {
    record["Type"]
    for record in records
    if record.get("Name") == auth_domain and "AliasTarget" in record
}

missing = expected_types - found
assert not missing, f"missing alias record types for auth site domain: {sorted(missing)}"
PY

# --- Deploy the auth-site SPA and run the BDD e2e suite ---------------------
#
# node-vlinder-auth is a separate repo. CI checks it out as a nested
# subdirectory of this checkout (see ct_terraform_integration.yml); local
# dev workspaces typically have it as a sibling of terraform-modules
# instead. Try both layouts; skip this whole block (with a clear message,
# not a hard failure) if neither is found, so a bare terraform-modules
# checkout can still run the rest of the suite.
resolve_node_vlinder_auth_dir() {
  local candidate
  for candidate in \
    "${script_dir}/../../../node-vlinder-auth" \
    "${script_dir}/../../../../node-vlinder-auth"; do
    if [ -d "${candidate}/packages/auth-site" ]; then
      (cd "${candidate}" && pwd)
      return 0
    fi
  done
  return 1
}

node_vlinder_auth_dir="$(resolve_node_vlinder_auth_dir || true)"

if [ -z "${node_vlinder_auth_dir}" ]; then
  printf '%s\n' "node-vlinder-auth checkout not found (tried CI-nested and sibling-workspace layouts); skipping auth-site SPA deploy and e2e suite." >&2
else
  auth_site_bucket_name="$(terraform -chdir="${script_dir}" output -raw auth_site_bucket_name)"
  auth_site_client_id="$(terraform -chdir="${script_dir}" output -raw auth_site_client_id)"
  role_assignments_table_name="$(terraform -chdir="${script_dir}" output -raw role_assignments_table_name)"
  auth_url="$(terraform -chdir="${script_dir}" output -raw auth_url)"

  # Install once, up front, before deploy.sh's own `npm run build` --
  # deploy.sh assumes node_modules already exists (it only builds, it never
  # installs), and on a fresh CI checkout of node-vlinder-auth nothing has
  # been installed yet at this point. Getting this ordering wrong is exactly
  # what caused the first real attempt at this to fail: tsc couldn't find
  # react/react-dom at all, not a real code problem.
  printf 'Installing node-vlinder-auth dependencies...\n'
  if ! (cd "${node_vlinder_auth_dir}" && npm install --no-audit --no-fund); then
    printf 'node-vlinder-auth npm install failed\n' >&2
    exit 1
  fi

  printf 'Deploying auth-site SPA to %s...\n' "${auth_site_bucket_name}"
  if ! "${node_vlinder_auth_dir}/packages/auth-site/scripts/deploy.sh" \
    --bucket "${auth_site_bucket_name}" \
    --client-id "${auth_site_client_id}"; then
    printf 'auth-site SPA deploy failed\n' >&2
    exit 1
  fi

  # Explicit exit-code check + exit, not just relying on set -e: a bare
  # failing command here previously did NOT fail this step in CI (the
  # EXIT trap's own cleanup path apparently ended up determining the final
  # exit status instead of the triggering failure), so the SPA-deploy
  # failure above was silently reported as an overall suite "success" the
  # first time this ran for real. Don't trust implicit propagation through
  # the trap for this block; make it explicit.
  printf 'Running e2e suite against %s...\n' "${auth_url}"
  if ! (
    cd "${node_vlinder_auth_dir}/e2e"
    npx playwright install chromium --with-deps

    export E2E_BASE_URL="${auth_url}"
    export E2E_USER_POOL_ID="${user_pool_id}"
    export E2E_ROLE_ASSIGNMENTS_TABLE="${role_assignments_table_name}"
    export AWS_REGION="${TF_VAR_aws_region}"
    npm run test:live
  ); then
    printf 'e2e suite failed\n' >&2
    exit 1
  fi
fi
