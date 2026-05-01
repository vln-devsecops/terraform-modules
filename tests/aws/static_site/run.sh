#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "${script_dir}/../_lib.sh"

cleanup() {
  local exit_code="$1"
  run_terraform_cleanup "${script_dir}" "${exit_code}"
}

trap 'cleanup "$?"' EXIT

base_domain="${STATIC_SITE_TEST_BASE_DOMAIN:-${MAIL_TEST_BASE_DOMAIN:-}}"
route53_zone_id="${STATIC_SITE_TEST_ROUTE53_ZONE_ID:-${MAIL_TEST_ROUTE53_ZONE_ID:-}}"

require_env AWS_ACCESS_KEY_ID "AWS_ACCESS_KEY_ID must be set to run the static-site live suite."
require_env AWS_SECRET_ACCESS_KEY "AWS_SECRET_ACCESS_KEY must be set to run the static-site live suite."

if [ -z "${base_domain}" ] || [ -z "${route53_zone_id}" ]; then
  printf '%s\n' "Set STATIC_SITE_TEST_BASE_DOMAIN and STATIC_SITE_TEST_ROUTE53_ZONE_ID (or reuse MAIL_TEST_BASE_DOMAIN and MAIL_TEST_ROUTE53_ZONE_ID) to run the static-site live suite." >&2
  exit 2
fi

export TF_VAR_name_suffix="${TF_VAR_name_suffix:-$(random_suffix)}"
export TF_VAR_aws_region="${TF_VAR_aws_region:-$(default_aws_region)}"
export TF_VAR_base_domain="${TF_VAR_base_domain:-${base_domain}}"
export TF_VAR_route53_zone_id="${TF_VAR_route53_zone_id:-${route53_zone_id}}"

terraform_init_apply "${script_dir}"

bucket_name="$(terraform -chdir="${script_dir}" output -raw bucket_name)"
distribution_id="$(terraform -chdir="${script_dir}" output -raw distribution_id)"
cloudfront_domain_name="$(terraform -chdir="${script_dir}" output -raw cloudfront_domain_name)"
site_name="$(terraform -chdir="${script_dir}" output -raw site_name)"

aws s3api head-bucket --bucket "${bucket_name}" >/dev/null

distribution_aliases="$(aws cloudfront get-distribution --id "${distribution_id}" --output json)"
python3 - "${distribution_aliases}" "${site_name}" "${cloudfront_domain_name}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
site_name = sys.argv[2]
cloudfront_domain_name = sys.argv[3]

distribution = payload["Distribution"]
aliases = distribution["DistributionConfig"]["Aliases"]["Items"]
assert site_name in aliases, f"expected {site_name!r} in distribution aliases {aliases!r}"
assert distribution["DomainName"] == cloudfront_domain_name, "cloudfront domain output mismatch"
assert distribution["Status"] in {"InProgress", "Deployed"}, "unexpected cloudfront status"
PY

record_payload="$(aws route53 list-resource-record-sets \
  --hosted-zone-id "${TF_VAR_route53_zone_id}" \
  --output json)"
python3 - "${record_payload}" "${site_name}." <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
site_name = sys.argv[2]
records = payload["ResourceRecordSets"]

expected_types = {"A", "AAAA"}
found = {
    record["Type"]
    for record in records
    if record.get("Name") == site_name and "AliasTarget" in record
}

missing = expected_types - found
assert not missing, f"missing alias record types: {sorted(missing)}"
PY
