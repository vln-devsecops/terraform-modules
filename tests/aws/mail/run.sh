#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "${script_dir}/../_lib.sh"

require_env "MAIL_TEST_BASE_DOMAIN" "MAIL_TEST_BASE_DOMAIN is required to run the mail integration suite."
require_env "MAIL_TEST_ROUTE53_ZONE_ID" "MAIL_TEST_ROUTE53_ZONE_ID is required to run the mail integration suite."

cleanup() {
  local exit_code="$1"
  run_terraform_cleanup "${script_dir}" "${exit_code}"
}

trap 'cleanup "$?"' EXIT

export TF_VAR_name_suffix="${TF_VAR_name_suffix:-$(random_suffix)}"
export TF_VAR_aws_region="${TF_VAR_aws_region:-$(default_aws_region)}"
export TF_VAR_base_domain="${TF_VAR_base_domain:-${MAIL_TEST_BASE_DOMAIN}}"
export TF_VAR_route53_zone_id="${TF_VAR_route53_zone_id:-${MAIL_TEST_ROUTE53_ZONE_ID}}"

terraform_init_apply "${script_dir}"

domain_name="$(terraform -chdir="${script_dir}" output -raw domain_name)"
mail_from_domain="$(terraform -chdir="${script_dir}" output -raw mail_from_domain)"
identity_arn="$(terraform -chdir="${script_dir}" output -raw identity_arn)"

[[ "${domain_name}" == "mail-${TF_VAR_name_suffix}.${TF_VAR_base_domain}" ]] || {
  printf 'expected domain name mail-%s.%s, got %s\n' "${TF_VAR_name_suffix}" "${TF_VAR_base_domain}" "${domain_name}" >&2
  exit 1
}

[[ "${mail_from_domain}" == "bounce.${domain_name}" ]] || {
  printf 'expected MAIL FROM domain bounce.%s, got %s\n' "${domain_name}" "${mail_from_domain}" >&2
  exit 1
}

[[ "${identity_arn}" == arn:aws:ses:* ]] || {
  printf 'expected an SES identity ARN, got %s\n' "${identity_arn}" >&2
  exit 1
}
