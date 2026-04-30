#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "${script_dir}/../_lib.sh"

cleanup() {
  local exit_code="$1"
  run_terraform_cleanup "${script_dir}" "${exit_code}"
}

trap 'cleanup "$?"' EXIT

export TF_VAR_name_suffix="${TF_VAR_name_suffix:-$(random_suffix)}"
export TF_VAR_aws_region="${TF_VAR_aws_region:-$(default_aws_region)}"

terraform_init_apply "${script_dir}"

table_name="$(terraform -chdir="${script_dir}" output -raw table_name)"
kms_key_arn="$(terraform -chdir="${script_dir}" output -raw kms_key_arn)"

[[ "${table_name}" == *"${TF_VAR_name_suffix}"* ]] || {
  printf 'expected table name to include suffix %s, got %s\n' "${TF_VAR_name_suffix}" "${table_name}" >&2
  exit 1
}

[[ "${kms_key_arn}" == arn:aws:kms:* ]] || {
  printf 'expected a KMS ARN, got %s\n' "${kms_key_arn}" >&2
  exit 1
}
