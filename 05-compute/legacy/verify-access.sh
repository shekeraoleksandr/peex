#!/usr/bin/env bash
# Verify virtual machine access (Trainee KEY): connect over SSH and confirm we
# are on the instance. Retries while the VM finishes booting.
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_login
load_state

{
echo "### VERIFY ACCESS @ $(date -u '+%F %T UTC')  ip=$PUBLIC_IP"
echo "== EC2 status checks =="
aws ec2 describe-instance-status --region "$REGION" --instance-ids "$INSTANCE_ID" \
    --query 'InstanceStatuses[0].{Instance:InstanceStatus.Status,System:SystemStatus.Status}' --output table 2>/dev/null || true

echo "== SSH connectivity (retry up to ~2.5 min) =="
ok=""
for i in $(seq 1 15); do
    if ssh_run 'echo SSH_OK' 2>/dev/null | grep -q SSH_OK; then ok=1; break; fi
    echo "  attempt $i: not ready yet, waiting 10s..."; sleep 10
done
[ -n "$ok" ] || { echo "SSH did not become available"; exit 1; }

echo "== Access confirmed — identity & host info =="
ssh_run 'echo "whoami: $(whoami)"; echo "id: $(id)"; echo "---"; uname -a; echo "---"; hostnamectl 2>/dev/null | head -8; echo "---"; uptime'
echo
echo "ACCESS VERIFIED"
} 2>&1 | tee "$PROOF/02_verify_access.txt"
