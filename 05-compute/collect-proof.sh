#!/usr/bin/env bash
# Compute-competency proof, pulled from the real EC2 web instance that
# ../11-network/terraform provisions (VPC + firewall + 2x EC2 is one shared
# stack -- see ../11-network/README.md). Run ../11-network/scripts/apply.sh
# FIRST (or at least `terraform apply` in ../11-network/terraform), then run
# this.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TFDIR="$HERE/../11-network/terraform"
PROOF="$HERE/proof"
mkdir -p "$PROOF"

cd "$TFDIR"
WEB_IP="$(terraform output -raw web_public_ip)"
KEY="$(terraform output -raw ssh_key_path)"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -i "$KEY")

{
echo "### COMPUTE PROOF @ $(date -u '+%F %T UTC')  (instance provisioned by ../11-network/terraform)"
echo

echo "===== 1) Provision: predefined type + image, running state ====="
aws ec2 describe-instances --filters "Name=tag:Name,Values=*-web" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].[InstanceId,InstanceType,ImageId,State.Name,LaunchTime]' --output text

echo
echo "===== 2) Verify VM access (SSH) ====="
ssh "${SSH_OPTS[@]}" "ubuntu@$WEB_IP" 'whoami; id; uname -a; hostnamectl'

echo
echo "===== 3) Basic OS configuration (applied by cloud-init, no manual steps) ====="
ssh "${SSH_OPTS[@]}" "ubuntu@$WEB_IP" '
  echo "-- nginx installed + enabled + active --"; systemctl is-enabled nginx; systemctl is-active nginx
  echo "-- hostname --"; hostname
  echo "-- served content --"; curl -s localhost/
'

echo
echo "===== 4) Monitor VM resource usage ====="
ssh "${SSH_OPTS[@]}" "ubuntu@$WEB_IP" '
  echo "-- uptime / load --"; uptime
  echo "-- memory --"; free -h
  echo "-- disk --"; df -h /
  echo "-- node_exporter (the metric source Prometheus scrapes) --"
  curl -s localhost:9100/metrics | grep -E "^node_(load1|memory_MemAvailable_bytes) "
'
echo "(the same CPU/memory numbers are also visible live in Grafana -- see ../11-network/proof)"

echo
echo "COMPUTE PROOF DONE"
} 2>&1 | tee "$PROOF/00_compute_proof.txt"
echo "==> Wrote $PROOF/00_compute_proof.txt"
