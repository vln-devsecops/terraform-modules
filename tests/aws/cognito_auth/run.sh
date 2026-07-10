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
hosted_ui_domain="$(terraform -chdir="${script_dir}" output -raw hosted_ui_domain)"
admin_panel_url="$(terraform -chdir="${script_dir}" output -raw admin_panel_url)"
admin_api_invoke_url="$(terraform -chdir="${script_dir}" output -raw admin_api_invoke_url)"

aws cognito-idp describe-user-pool --user-pool-id "${user_pool_id}" >/dev/null

# The hosted-UI domain's CloudFront distribution can take a few minutes to
# report Deployed after creation; describe-user-pool-domain succeeding
# (regardless of status) is enough to confirm the domain itself was created
# and is queryable.
aws cognito-idp describe-user-pool-domain --domain "${hosted_ui_domain}" >/dev/null

python3 - "${admin_panel_url}" "${admin_api_invoke_url}" <<'PY'
import sys

admin_panel_url, admin_api_invoke_url = sys.argv[1], sys.argv[2]
assert admin_panel_url.startswith("https://"), f"unexpected admin_panel_url: {admin_panel_url!r}"
assert admin_api_invoke_url.startswith("https://"), f"unexpected admin_api_invoke_url: {admin_api_invoke_url!r}"
PY

record_payload="$(aws route53 list-resource-record-sets \
  --hosted-zone-id "${TF_VAR_route53_zone_id}" \
  --output json)"
python3 - "${record_payload}" "${hosted_ui_domain}." <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
hosted_ui_domain = sys.argv[2]
records = payload["ResourceRecordSets"]

expected_types = {"A", "AAAA"}
found = {
    record["Type"]
    for record in records
    if record.get("Name") == hosted_ui_domain and "AliasTarget" in record
}

missing = expected_types - found
assert not missing, f"missing alias record types for hosted UI domain: {sorted(missing)}"
PY
