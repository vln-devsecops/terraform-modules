#!/usr/bin/env bash

set -euo pipefail

random_suffix() {
  python3 - <<'PY'
import secrets
import string

alphabet = string.ascii_lowercase + string.digits
print("".join(secrets.choice(alphabet) for _ in range(8)))
PY
}

default_aws_region() {
  if [ -n "${TF_VAR_aws_region:-}" ]; then
    printf '%s\n' "${TF_VAR_aws_region}"
  elif [ -n "${AWS_REGION:-}" ]; then
    printf '%s\n' "${AWS_REGION}"
  elif [ -n "${AWS_DEFAULT_REGION:-}" ]; then
    printf '%s\n' "${AWS_DEFAULT_REGION}"
  else
    printf 'us-east-1\n'
  fi
}

require_env() {
  local var_name="$1"
  local message="$2"

  if [ -z "${!var_name:-}" ]; then
    printf '%s\n' "${message}" >&2
    exit 2
  fi
}

should_capture_terraform_state() {
  [ "${TF_LIVE_SUITE_CAPTURE_TFSTATE:-0}" = "1" ]
}

snapshot_terraform_state() {
  local dir="$1"
  local phase="$2"
  local snapshot_dir="${dir}/.cleanup-state"

  mkdir -p "${snapshot_dir}"

  if [ -f "${dir}/terraform.tfstate" ]; then
    cp "${dir}/terraform.tfstate" "${snapshot_dir}/${phase}.tfstate"
  fi

  if [ -f "${dir}/terraform.tfstate.backup" ]; then
    cp "${dir}/terraform.tfstate.backup" "${snapshot_dir}/${phase}.tfstate.backup"
  fi

  if [ -f "${dir}/crash.log" ]; then
    cp "${dir}/crash.log" "${snapshot_dir}/${phase}.crash.log"
  fi

  if [ -f "${dir}/.terraform.lock.hcl" ]; then
    cp "${dir}/.terraform.lock.hcl" "${snapshot_dir}/.terraform.lock.hcl"
  fi
}

cleanup_terraform_dir() {
  local dir="$1"

  rm -rf \
    "${dir}/.terraform" \
    "${dir}/terraform.tfstate" \
    "${dir}/terraform.tfstate.backup" \
    "${dir}/crash.log" \
    "${dir}/.tmp"
}

terraform_init_apply() {
  local dir="$1"
  terraform -chdir="${dir}" init -input=false
  terraform -chdir="${dir}" apply -auto-approve -input=false
}

terraform_destroy() {
  local dir="$1"
  terraform -chdir="${dir}" destroy -auto-approve -input=false
}

run_terraform_cleanup() {
  local dir="$1"
  local exit_code="$2"
  local destroy_failed=0

  if [ -f "${dir}/terraform.tfstate" ] || [ -f "${dir}/terraform.tfstate.backup" ]; then
    if should_capture_terraform_state; then
      snapshot_terraform_state "${dir}" "pre-destroy"
    fi

    if ! terraform_destroy "${dir}"; then
      destroy_failed=1
      printf 'terraform destroy failed in %s; preserving Terraform state for inspection\n' "${dir}" >&2

      if should_capture_terraform_state; then
        snapshot_terraform_state "${dir}" "post-destroy-failed"
      fi
    fi
  fi

  if [ "${destroy_failed}" -eq 0 ]; then
    cleanup_terraform_dir "${dir}"
  fi

  if [ "${exit_code}" -ne 0 ]; then
    return "${exit_code}"
  fi

  if [ "${destroy_failed}" -ne 0 ]; then
    return 1
  fi
}
