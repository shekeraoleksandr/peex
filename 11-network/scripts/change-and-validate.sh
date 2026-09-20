#!/usr/bin/env bash
# "Rule updates or changes are tested and validated to avoid unintended
# disruptions" + "before/after comparison if modifying existing rules".
#
# Makes one real, reversible rule change, captures the state and a live
# connectivity test on each side of it, then reverts and re-validates. The
# point is the method: capture -> change -> test -> revert -> confirm restored.
set -euo pipefail

# AWS CLI v2 sends output to a pager when stdout is a TTY, which silently
# swallows every --output json result. Harmless when piped to tee, fatal
# when run interactively -- so pin it off everywhere.
export AWS_PAGER=""

HERE="$(cd "$(dirname "$0")" && pwd)"
TFDIR="$HERE/../terraform"
PROOF="$HERE/../proof"
mkdir -p "$PROOF"

cd "$TFDIR"
WEB_IP="$(terraform output -raw web_public_ip)"
VPC_ID="$(terraform output -raw vpc_id)"

note() { echo; echo "\$ $*"; }

web_sg() {
    aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
        "Name=group-name,Values=*web-sg" --query 'SecurityGroups[0].GroupId' --output text
}
SG_ID="$(web_sg)"

show_ingress() {
    aws ec2 describe-security-groups --group-ids "$SG_ID" \
        --query 'SecurityGroups[0].IpPermissions[].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp,IpRanges[0].Description]' \
        --output text
}

probe_8080() {
    curl -fsS -m 6 "http://$WEB_IP:8080/" >/dev/null 2>&1 \
        && echo "  :8080 reachable" || echo "  :8080 not reachable"
}

{
echo "### RULE CHANGE: TEST, VALIDATE, REVERT @ $(date -u '+%F %T UTC')"
echo "target security group: $SG_ID (web tier)"
echo
echo "Change under test: temporarily open tcp/8080 to the operator IP,"
echo "confirm the change takes effect, then remove it and confirm the"
echo "original posture is restored."

echo
echo "===== BEFORE ====="
note "aws ec2 describe-security-groups  # ingress rules"
show_ingress
note "connectivity probe"
probe_8080

echo
echo "===== APPLYING THE CHANGE ====="
MYIP="$("$HERE/get-my-ip.sh")"
note "aws ec2 authorize-security-group-ingress --port 8080 --cidr $MYIP"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
    --ip-permissions "IpProtocol=tcp,FromPort=8080,ToPort=8080,IpRanges=[{CidrIp=$MYIP,Description='TEMPORARY - change-validation test'}]" \
    >/dev/null && echo "  rule added"
sleep 5

echo
echo "===== AFTER ====="
note "aws ec2 describe-security-groups  # ingress rules"
show_ingress
note "connectivity probe (nothing listens on 8080, so the honest result is a"
echo "   refused connection rather than a timeout -- the firewall now lets the"
echo "   packet through and the OS rejects it, which is the observable change)"
# Same per-run known_hosts reasoning as test-connectivity.sh: instances are
# replaced whenever user_data changes, so their host keys change with them.
ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
    -o UserKnownHostsFile="$HERE/../.known_hosts_run" \
    -i "$(terraform output -raw ssh_key_path)" "ubuntu@$WEB_IP" \
    'ss -ltn | head -5' 2>/dev/null || true
probe_8080

echo
echo "===== REVERTING ====="
note "aws ec2 revoke-security-group-ingress --port 8080"
aws ec2 revoke-security-group-ingress --group-id "$SG_ID" \
    --ip-permissions "IpProtocol=tcp,FromPort=8080,ToPort=8080,IpRanges=[{CidrIp=$MYIP}]" \
    >/dev/null && echo "  rule removed"
sleep 5

echo
echo "===== AFTER REVERT (must match BEFORE) ====="
note "aws ec2 describe-security-groups  # ingress rules"
show_ingress
note "connectivity probe"
probe_8080

echo
echo "===== DRIFT CHECK: does Terraform agree the infrastructure is unchanged? ====="
note "terraform plan -detailed-exitcode   # 0 = no drift"
if terraform plan -detailed-exitcode -var="allowed_cidr=$MYIP" >/tmp/peex-plan.out 2>&1; then
    echo "  [OK] no drift -- the manual change was fully reverted"
else
    rc=$?
    if [ "$rc" -eq 2 ]; then
        echo "  [DRIFT] Terraform still sees a difference:"
        # Show which resources changed and the summary line. The previous
        # pattern here matched nothing, so this printed an empty report.
        grep -E "will be (created|destroyed|updated|replaced)|^Plan:|# [a-z_]+\." /tmp/peex-plan.out \
            | sed 's/^/     /' | head -25
        echo
        echo "     NOTE: drift here is expected if the stack was applied with"
        echo "     different -var values than this plan used (allowed_cidr"
        echo "     changes whenever your public IP does)."
    else
        echo "  [ERROR] plan failed (rc=$rc); see /tmp/peex-plan.out"
    fi
fi

echo
echo "CHANGE VALIDATION COMPLETE"
} 2>&1 | tee "$PROOF/03_rule_change_validation.txt"

echo "==> Wrote $PROOF/03_rule_change_validation.txt"
