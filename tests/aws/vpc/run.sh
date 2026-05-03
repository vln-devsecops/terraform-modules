#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "${script_dir}/../_lib.sh"

cleanup() {
  local exit_code="$1"
  run_terraform_cleanup "${script_dir}" "${exit_code}"
}

trap 'cleanup "$?"' EXIT

require_env AWS_ACCESS_KEY_ID "AWS_ACCESS_KEY_ID must be set to run the vpc live suite."
require_env AWS_SECRET_ACCESS_KEY "AWS_SECRET_ACCESS_KEY must be set to run the vpc live suite."

export TF_VAR_name_suffix="${TF_VAR_name_suffix:-$(random_suffix)}"
export TF_VAR_aws_region="${TF_VAR_aws_region:-$(default_aws_region)}"

terraform_init_apply "${script_dir}"

vpc_id="$(terraform -chdir="${script_dir}" output -raw vpc_id)"
vpc_cidr="$(terraform -chdir="${script_dir}" output -raw vpc_cidr)"
igw_id="$(terraform -chdir="${script_dir}" output -raw internet_gateway_id)"
rt_id="$(terraform -chdir="${script_dir}" output -raw public_route_table_id)"

[[ "${vpc_id}" == vpc-* ]] || {
  printf 'expected VPC ID starting with vpc-, got %s\n' "${vpc_id}" >&2
  exit 1
}

[[ "${vpc_cidr}" == "10.42.0.0/16" ]] || {
  printf 'expected VPC CIDR 10.42.0.0/16, got %s\n' "${vpc_cidr}" >&2
  exit 1
}

[[ "${igw_id}" == igw-* ]] || {
  printf 'expected IGW ID starting with igw-, got %s\n' "${igw_id}" >&2
  exit 1
}

[[ "${rt_id}" == rtb-* ]] || {
  printf 'expected route table ID starting with rtb-, got %s\n' "${rt_id}" >&2
  exit 1
}

# Verify subnets exist and count matches.
subnet_ids_json="$(terraform -chdir="${script_dir}" output -json public_subnet_ids)"
python3 - "${subnet_ids_json}" "${vpc_id}" <<'PY'
import json
import sys

subnet_ids = json.loads(sys.argv[1])
vpc_id = sys.argv[2]

assert len(subnet_ids) == 2, f"expected 2 subnet IDs, got {len(subnet_ids)}: {subnet_ids}"
for sid in subnet_ids:
    assert sid.startswith("subnet-"), f"expected subnet ID starting with subnet-, got {sid!r}"

print(f"vpc live suite: VPC {vpc_id} has {len(subnet_ids)} subnets — OK")
PY

# Verify IGW is attached to the VPC.
igw_payload="$(aws ec2 describe-internet-gateways \
  --internet-gateway-ids "${igw_id}" \
  --output json)"
python3 - "${igw_payload}" "${vpc_id}" "${igw_id}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
vpc_id = sys.argv[2]
igw_id = sys.argv[3]

igw = payload["InternetGateways"][0]
attachments = igw.get("Attachments", [])
attached_vpcs = [a["VpcId"] for a in attachments if a.get("State") == "available"]
assert vpc_id in attached_vpcs, f"IGW {igw_id} not attached to VPC {vpc_id}; attachments: {attachments}"

print(f"vpc live suite: IGW {igw_id} attached to {vpc_id} — OK")
PY

# Verify the route table has a default route via the IGW.
rt_payload="$(aws ec2 describe-route-tables \
  --route-table-ids "${rt_id}" \
  --output json)"
python3 - "${rt_payload}" "${igw_id}" "${rt_id}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
igw_id = sys.argv[2]
rt_id = sys.argv[3]

rt = payload["RouteTables"][0]
routes = rt.get("Routes", [])
default_routes = [
    r for r in routes
    if r.get("DestinationCidrBlock") == "0.0.0.0/0"
    and r.get("GatewayId") == igw_id
    and r.get("State") == "active"
]
assert default_routes, f"Route table {rt_id} has no active 0.0.0.0/0 route via IGW {igw_id}; routes: {routes}"

print(f"vpc live suite: route table {rt_id} has default route via {igw_id} — OK")
PY
