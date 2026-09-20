#!/usr/bin/env bash
# Tear down the whole VPC + firewall + EC2 + monitoring stack (avoid lingering cost).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/../terraform"
read -r -p "Destroy the whole VPC + EC2 + monitoring stack? [y/N] " ans
[ "${ans:-N}" = "y" ] || [ "${ans:-N}" = "Y" ] || { echo "aborted"; exit 0; }
terraform destroy
