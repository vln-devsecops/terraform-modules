#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "${script_dir}/../../_lib.sh"

cleanup() {
  terraform_destroy_quiet "${script_dir}"
  cleanup_terraform_dir "${script_dir}"
}

trap cleanup EXIT

export TF_VAR_name_suffix="${TF_VAR_name_suffix:-$(random_suffix)}"
export TF_VAR_aws_region="${TF_VAR_aws_region:-$(default_aws_region)}"

terraform_init_apply "${script_dir}"

function_name="$(terraform -chdir="${script_dir}" output -raw function_name)"
secret_name="$(terraform -chdir="${script_dir}" output -raw secret_name)"
url="$(terraform -chdir="${script_dir}" output -raw url)"
kms_key_arn="$(terraform -chdir="${script_dir}" output -raw kms_key_arn)"

[[ "${function_name}" == *"${TF_VAR_name_suffix}"* ]] || {
  printf 'expected function name to include suffix %s, got %s\n' "${TF_VAR_name_suffix}" "${function_name}" >&2
  exit 1
}

[[ "${secret_name}" == *"${TF_VAR_name_suffix}"* ]] || {
  printf 'expected secret name to include suffix %s, got %s\n' "${TF_VAR_name_suffix}" "${secret_name}" >&2
  exit 1
}

[[ "${url}" == https://* ]] || {
  printf 'expected a Lambda URL, got %s\n' "${url}" >&2
  exit 1
}

[[ "${kms_key_arn}" == arn:aws:kms:* ]] || {
  printf 'expected a KMS ARN, got %s\n' "${kms_key_arn}" >&2
  exit 1
}
