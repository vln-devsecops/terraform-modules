#!/usr/bin/env bash

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

terraform_init_apply "${script_dir}"

function_name="$(terraform -chdir="${script_dir}" output -raw function_name)"
role_name="$(terraform -chdir="${script_dir}" output -raw role_name)"
secret_name="$(terraform -chdir="${script_dir}" output -raw secret_name)"
url="$(terraform -chdir="${script_dir}" output -raw url)"
kms_key_arn="$(terraform -chdir="${script_dir}" output -raw kms_key_arn)"
expected_role_name="$(python - <<'PY'
import hashlib
import os

suffix = os.environ["TF_VAR_name_suffix"]
app_name = f"sampleapp-{suffix}"
print(f"iam_for_lambda_origin-response_dev_{hashlib.md5(app_name.encode()).hexdigest()[:8]}")
PY
)"

[[ "${function_name}" == *"${TF_VAR_name_suffix}"* ]] || {
  printf 'expected function name to include suffix %s, got %s\n' "${TF_VAR_name_suffix}" "${function_name}" >&2
  exit 1
}

[[ "${secret_name}" == *"${TF_VAR_name_suffix}"* ]] || {
  printf 'expected secret name to include suffix %s, got %s\n' "${TF_VAR_name_suffix}" "${secret_name}" >&2
  exit 1
}

[[ "${role_name}" == "${expected_role_name}" ]] || {
  printf 'expected role name %s, got %s\n' "${expected_role_name}" "${role_name}" >&2
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
