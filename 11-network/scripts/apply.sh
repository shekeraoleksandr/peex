#!/usr/bin/env bash
# Provision the VPC + firewall + 2 EC2 instances (web + monitoring) with
# Terraform, wait for cloud-init to finish, then collect proof.
# Run on the machine where your `aws` CLI is logged in (region us-east-1).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TFDIR="$HERE/../terraform"

if [ -z "${TF_VAR_allowed_cidr:-}" ] && [ ! -f "$TFDIR/terraform.tfvars" ]; then
    ip="$("$HERE/get-my-ip.sh")"
    echo "==> No allowed_cidr set. Detected your public IP: $ip"
    export TF_VAR_allowed_cidr="$ip"
fi

cd "$TFDIR"
terraform init
terraform plan -out=tfplan
terraform apply tfplan

echo "==> Waiting 150s for cloud-init on all five hosts"
echo "    (nginx, node_exporter, Docker+Prometheus+Grafana, NAT rules, strongSwan)"
sleep 150

"$HERE/collect-proof.sh"

echo
echo "==> Now prove the traffic controls behave as designed:"
echo "      ./test-connectivity.sh     # allowed vs blocked matrix"
echo "      ./change-and-validate.sh   # rule change, before/after, revert"
