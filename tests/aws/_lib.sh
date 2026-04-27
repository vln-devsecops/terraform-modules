#!/usr/bin/env bash

set -euo pipefail

random_suffix() {
  tr -dc 'a-z0-9' </dev/urandom | head -c 8
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

cleanup_terraform_dir() {
  local dir="$1"

  rm -rf \
    "${dir}/.terraform" \
    "${dir}/.terraform.lock.hcl" \
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

terraform_destroy_quiet() {
  local dir="$1"
  terraform -chdir="${dir}" destroy -auto-approve -input=false >/dev/null 2>&1 || true
}
