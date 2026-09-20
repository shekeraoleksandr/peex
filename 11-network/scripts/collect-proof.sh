#!/usr/bin/env bash
# Pull live proof from the applied infrastructure: VPC/subnet/routing, the
# security-group firewall, both EC2 instances, and the Prometheus/Grafana
# stack. Run after ../terraform has been applied (apply.sh does this for you).
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
WEB_PRIVATE_IP="$(terraform output -raw web_private_ip)"
MON_IP="$(terraform output -raw monitoring_public_ip)"
KEY="$(terraform output -raw ssh_key_path)"
VPC_ID="$(terraform output -raw vpc_id)"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -i "$KEY")

# `curl <url> | head -n` kills curl with SIGPIPE (exit 23) as soon as head has
# its lines; under `set -o pipefail` + `set -e` that aborts this whole script
# on a request that actually succeeded. Capture first, page from a here-string.
http_show() {                       # http_show <url> [lines]
    local url="$1" lines="${2:-20}" resp rc=0 code
    resp="$(curl -sS -i -m 10 "$url" 2>&1)" || rc=$?
    head -n "$lines" <<<"$resp"
    code="$(awk 'NR==1 && /^HTTP/{print $2; exit}' <<<"$resp")"
    if [ -n "$code" ]; then echo "  [HTTP $code -- ${#resp} bytes received]"
    else echo "  (no HTTP response -- curl exit $rc)"; fi
}

{
echo "### NETWORK + COMPUTE + OBSERVABILITY PROOF @ $(date -u '+%F %T UTC')"
echo "vpc=$VPC_ID  web=$WEB_IP ($WEB_PRIVATE_IP)  monitoring=$MON_IP"
echo

echo "===== VPC / subnet / route table ====="
aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --query 'Vpcs[0].[VpcId,CidrBlock,State]' --output text
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[].[SubnetId,CidrBlock,AvailabilityZone,MapPublicIpOnLaunch]' --output text
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[].Routes[].[DestinationCidrBlock,GatewayId]' --output text

echo
echo "===== Security groups (the firewall) ====="
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[].[GroupName,Description]' --output text
echo "-- web SG rules --"
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=*web-sg" \
    --query 'SecurityGroups[0].IpPermissions' --output json
echo "-- monitoring SG rules --"
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=*monitoring-sg" \
    --query 'SecurityGroups[0].IpPermissions' --output json

echo
echo "===== EC2 instances ====="
aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,InstanceId,InstanceType,PrivateIpAddress,PublicIpAddress,State.Name]' \
    --output text

echo
echo "===== Web instance: nginx + node_exporter (over SSH) ====="
ssh "${SSH_OPTS[@]}" "ubuntu@$WEB_IP" '
  echo "-- systemctl nginx --"; systemctl is-active nginx; systemctl is-enabled nginx
  echo "-- systemctl node_exporter --"; systemctl is-active node_exporter; systemctl is-enabled node_exporter
  echo "-- node_exporter local curl --"; m=$(curl -fsS -m 6 localhost:9100/metrics) && head -5 <<<"$m" || echo "(node_exporter not answering)"
'

echo
echo "===== Web instance reachable from the internet (nginx on 80) ====="
http_show "http://$WEB_IP/" 20

echo
echo "===== Firewall proof: node_exporter (9100) is NOT reachable from the internet ====="
echo "(expected: times out / refused -- it's only open to the monitoring instance's SG)"
# NOTE: curl's own -m does the timing out. Do NOT wrap this in `timeout`:
# macOS has no GNU `timeout`, so "command not found" would exit non-zero and
# be misread as "blocked", turning this check into a false positive.
fw_rc=0
curl -sS -m 6 "http://$WEB_IP:9100/metrics" >/dev/null 2>&1 || fw_rc=$?
if [ "$fw_rc" -eq 0 ]; then
    echo "UNEXPECTED: node_exporter IS reachable from the internet -- check the security group!"
else
    echo "confirmed: blocked from the internet (curl exit $fw_rc; 28=timed out, 7=refused -- both mean the SG dropped it)"
fi
echo "-- for contrast, the same port IS reachable from the monitoring instance --"
ssh "${SSH_OPTS[@]}" "ubuntu@$MON_IP" "out=\$(curl -fsS -m 6 http://$WEB_PRIVATE_IP:9100/metrics) && head -3 <<<\"\$out\"" \
    || echo "(monitoring instance could not scrape it either -- check cloud-init)"

echo
echo "===== Monitoring instance: docker + prometheus + grafana (over SSH) ====="
ssh "${SSH_OPTS[@]}" "ubuntu@$MON_IP" '
  echo "-- running containers --"
  sudo docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
  echo "-- cloud-init tail --"; sudo tail -5 /var/log/peex-userdata.log
'

echo
echo "===== Prometheus targets (web-instance should be UP, scraped over the private VPC IP) ====="
curl -sS "http://$MON_IP:9090/api/v1/targets" | python3 -m json.tool 2>/dev/null || curl -sS "http://$MON_IP:9090/api/v1/targets"

echo
echo "===== Grafana health ====="
curl -sS "http://$MON_IP:3000/api/health"; echo

echo
echo "PROOF DONE"
} 2>&1 | tee "$PROOF/00_network_compute_observability_proof.txt"

echo "==> Wrote $PROOF/00_network_compute_observability_proof.txt"
echo "==> Web:        http://$WEB_IP/"
echo "==> Grafana:    http://$MON_IP:3000  (admin / peexdemo123)"
echo "==> Prometheus: http://$MON_IP:9090"
