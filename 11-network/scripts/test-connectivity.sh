#!/usr/bin/env bash
# Prove the network controls behave as designed: what must flow, flows; what
# must be blocked, is blocked. Every check states its expectation up front, so
# a failed negative test is visible rather than silently passing.
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
WEB_PRIV="$(terraform output -raw web_private_ip)"
MON_IP="$(terraform output -raw monitoring_public_ip)"
PRIV_IP="$(terraform output -raw private_host_ip)"
PEER_IP="$(terraform output -raw peer_host_ip)"
PEER_PUB="$(terraform output -raw peer_host_public_ip)"
VPC_ID="$(terraform output -raw vpc_id)"
KEY="$(terraform output -raw ssh_key_path)"
case "$KEY" in /*) ;; *) KEY="$TFDIR/${KEY#./}" ;; esac
LOG_GROUP="$(terraform output -raw flow_log_group)"

# Every `terraform apply` that changes user_data REPLACES the instances, so
# they come back with new SSH host keys at the same addresses. Against the
# user's real known_hosts that reads as REMOTE HOST IDENTIFICATION HAS CHANGED
# and every SSH-based check fails at the front door -- which is exactly what
# happened on the first run of this script. A per-run known_hosts file keeps
# verification honest within a run without ever hitting a stale key, and
# leaves ~/.ssh/known_hosts untouched.
KNOWN_HOSTS="$HERE/../.known_hosts_run"
rm -f "$KNOWN_HOSTS"

SSH_BASE=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS" -i "$KEY")
SSH_OPTS=("${SSH_BASE[@]}" -o ConnectTimeout=15)
# The private host has no public address; reach it through the web instance.
PROXY="ssh -i $KEY -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$KNOWN_HOSTS -W %h:%p ubuntu@$WEB_IP"
SSH_PRIV=("${SSH_BASE[@]}" -o ConnectTimeout=20 -o "ProxyCommand=$PROXY")

note() { echo; echo "\$ $*"; }

# Run a check whose expected outcome is known. $1=expect(pass|fail) $2=label, rest=command
check() {
    local expect="$1" label="$2"; shift 2
    local rc=0
    "$@" >/tmp/peex-check.out 2>&1 || rc=$?
    if [ "$expect" = "pass" ]; then
        if [ "$rc" -eq 0 ]; then echo "  [OK]      $label"
        else echo "  [FAILED]  $label  (expected success, rc=$rc)"; sed 's/^/            /' /tmp/peex-check.out | head -3; fi
    else
        if [ "$rc" -ne 0 ]; then echo "  [BLOCKED] $label  (expected: denied, rc=$rc)"
        else echo "  [LEAK!]   $label  -- this SHOULD have been blocked"; fi
    fi
}

{
echo "### NETWORK CONTROLS: CONNECTIVITY MATRIX @ $(date -u '+%F %T UTC')"
echo "vpc=$VPC_ID"
echo "web      public=$WEB_IP  private=$WEB_PRIV"
echo "monitor  public=$MON_IP"
echo "private  $PRIV_IP  (no public address by design)"
echo "peer     $PEER_IP  (other VPC, via peering)"

echo
echo "=========================================================="
echo " 1. PUBLIC TIER — only the declared ports, only from my IP"
echo "=========================================================="
check pass    "nginx :80 on the web instance, from my IP"        curl -fsS -m 8 "http://$WEB_IP/"
check fail    "node_exporter :9100 from the internet"            curl -fsS -m 8 "http://$WEB_IP:9100/metrics"
check fail    "an undeclared port (:8080) on the web instance"   curl -fsS -m 6 "http://$WEB_IP:8080/"
check pass    "Grafana :3000 on the monitoring instance"         curl -fsS -m 8 "http://$MON_IP:3000/api/health"

echo
echo "  (9100 is open ONLY to the monitoring security group -- same port,"
echo "   different source, opposite result:)"
note "ssh monitoring -> curl http://$WEB_PRIV:9100/metrics"
ssh "${SSH_OPTS[@]}" "ubuntu@$MON_IP" "out=\$(curl -fsS -m 8 http://$WEB_PRIV:9100/metrics) && head -3 <<<\"\$out\"" \
    && echo "  [OK]      scrape from the monitoring SG succeeds" \
    || echo "  [FAILED]  monitoring could not scrape"

echo
echo "=========================================================="
echo " 2. PRIVATE TIER — no inbound path from the internet"
echo "=========================================================="
note "aws ec2 describe-instances  # does the private host even have a public IP?"
aws ec2 describe-instances --filters "Name=private-ip-address,Values=$PRIV_IP" \
    --query 'Reservations[].Instances[].[InstanceId,PrivateIpAddress,PublicIpAddress,SubnetId]' --output text

check fail "SSH to the private host directly from the internet" \
      ssh "${SSH_BASE[@]}" -o ConnectTimeout=8 "ubuntu@$PRIV_IP" true

echo
echo "  Reached instead through the web instance (internal routing between"
echo "  the public and private subnets):"
note "ssh -J web ubuntu@$PRIV_IP 'hostname; ip -4 addr show'"
ssh "${SSH_PRIV[@]}" "ubuntu@$PRIV_IP" 'hostname; ip -o -4 addr show | grep -v " lo "' \
    && echo "  [OK]      subnet-to-subnet reachability confirmed" \
    || echo "  [FAILED]  could not reach the private host internally"

echo
echo "=========================================================="
echo " 3. NAT — private subnet has egress but no ingress"
echo "=========================================================="
note "ssh -J web private -> curl https://checkip.amazonaws.com"
EGRESS_IP="$(ssh "${SSH_PRIV[@]}" "ubuntu@$PRIV_IP" 'curl -fsS -m 15 https://checkip.amazonaws.com' 2>/dev/null | tr -d '[:space:]' || true)"
NAT_IP="$(terraform output -raw nat_instance_public_ip)"
if [ -n "$EGRESS_IP" ]; then
    echo "  private host egresses as: $EGRESS_IP"
    echo "  NAT instance public IP:   $NAT_IP"
    [ "$EGRESS_IP" = "$NAT_IP" ] \
        && echo "  [OK]      egress is translated through the NAT instance" \
        || echo "  [NOTE]    egress IP differs from the NAT IP -- check the private route table"
else
    echo "  [FAILED]  no egress from the private subnet"
    echo "  -- NAT instance boot log (the cause is usually here) --"
    NAT_PUB="$(terraform output -raw nat_instance_public_ip)"
    ssh "${SSH_OPTS[@]}" "ubuntu@$NAT_PUB" \
        'sudo tail -15 /var/log/peex-userdata.log; echo "--- ip_forward:"; cat /proc/sys/net/ipv4/ip_forward; echo "--- nat table:"; sudo iptables -t nat -L POSTROUTING -n' \
        2>&1 | sed 's/^/     /' || echo "     (could not reach the NAT instance)"
fi

note "route table for the private subnet (0.0.0.0/0 must point at the NAT ENI, not the IGW)"
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=private" \
    --query 'RouteTables[].Routes[].[DestinationCidrBlock,GatewayId,NetworkInterfaceId,VpcPeeringConnectionId]' --output text

echo
echo "=========================================================="
echo " 4. PEERING — two private networks, both directions"
echo "=========================================================="
note "private host ($PRIV_IP) -> peer host ($PEER_IP)"
ssh "${SSH_PRIV[@]}" "ubuntu@$PRIV_IP" "ping -c 3 -W 3 $PEER_IP" \
    && echo "  [OK]      main -> peer" || echo "  [FAILED]  main -> peer"

note "peer host ($PEER_IP) -> private host ($PRIV_IP)   # symmetric routing"
# Reached by jumping through the web instance and across the peering link:
# the peer security group admits SSH only from the main VPC, never from the
# internet, so connecting to its public IP would (correctly) be refused.
ssh "${SSH_BASE[@]}" -o ConnectTimeout=20 -o "ProxyCommand=$PROXY" \
    "ubuntu@$PEER_IP" "ping -c 3 -W 3 $PRIV_IP" \
    && echo "  [OK]      peer -> main" || echo "  [FAILED]  peer -> main"

note "peering connection state"
aws ec2 describe-vpc-peering-connections \
    --query 'VpcPeeringConnections[].[VpcPeeringConnectionId,Status.Code,RequesterVpcInfo.CidrBlock,AccepterVpcInfo.CidrBlock]' --output text

echo
echo "=========================================================="
echo " 5. ENCRYPTION IN TRANSIT — IPsec over the peering link"
echo "=========================================================="
note "ipsec statusall  # SA state and the negotiated cipher suite"
ssh "${SSH_PRIV[@]}" "ubuntu@$PRIV_IP" 'sudo ipsec statusall 2>/dev/null | head -30' || true

note "tcpdump: traffic between the hosts must be ESP, not readable ICMP"
ssh "${SSH_PRIV[@]}" "ubuntu@$PRIV_IP" "
  sudo timeout 12 tcpdump -n -c 8 -i any host $PEER_IP 2>/dev/null &
  sleep 2; ping -c 4 -W 2 $PEER_IP >/dev/null 2>&1; wait
" || true
echo "  (ESP packets = payload encrypted; plain 'ICMP echo request' lines would mean the tunnel is down)"

echo
echo "=========================================================="
echo " 6. SUBNET-LEVEL FILTERING — Network ACLs"
echo "=========================================================="
note "public NACL rules"
aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=public" \
    --query 'NetworkAcls[].Entries[].[RuleNumber,Egress,Protocol,RuleAction,CidrBlock,PortRange.From,PortRange.To]' --output text

note "private NACL rules (note: no rule admits 0.0.0.0/0 inbound except ephemeral return traffic)"
aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=private" \
    --query 'NetworkAcls[].Entries[].[RuleNumber,Egress,Protocol,RuleAction,CidrBlock,PortRange.From,PortRange.To]' --output text

echo
echo "=========================================================="
echo " 7. EGRESS RESTRICTION — no 0.0.0.0/0 all-protocols rule"
echo "=========================================================="
note "egress rules per security group"
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[].{Name:GroupName,Egress:IpPermissionsEgress[].{Proto:IpProtocol,From:FromPort,To:ToPort,Cidr:IpRanges[0].CidrIp,Why:IpRanges[0].Description}}' \
    --output json

note "# a blocked outbound port proves egress really is restricted"
ssh "${SSH_OPTS[@]}" "ubuntu@$WEB_IP" 'timeout 8 curl -fsS -m 6 http://example.com:8888/ >/dev/null 2>&1; echo "rc=$?  (non-zero = egress on :8888 denied as intended)"' || true

echo
echo "=========================================================="
echo " 8. TRAFFIC MONITORING — VPC Flow Logs"
echo "=========================================================="
note "aws logs describe-log-groups  # flow logs enabled?"
aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" \
    --query 'logGroups[].[logGroupName,retentionInDays,storedBytes]' --output text

note "recent REJECT records (the denials above, recorded independently)"
STREAM="$(aws logs describe-log-streams --log-group-name "$LOG_GROUP" \
    --order-by LastEventTime --descending --max-items 1 \
    --query 'logStreams[0].logStreamName' --output text 2>/dev/null || true)"
if [ -n "${STREAM:-}" ] && [ "$STREAM" != "None" ]; then
    aws logs get-log-events --log-group-name "$LOG_GROUP" --log-stream-name "$STREAM" \
        --limit 200 --query 'events[].message' --output text 2>/dev/null \
        | grep -i "REJECT" | head -10 \
        || echo "  (no REJECT records in this stream yet -- flow logs lag by up to ~10 min)"
else
    echo "  (no log streams yet -- flow logs take several minutes to first publish)"
fi

echo
echo "=========================================================="
echo " 9. PRIVATE ACCESS TO S3 — gateway endpoint"
echo "=========================================================="
note "aws ec2 describe-vpc-endpoints"
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'VpcEndpoints[].[VpcEndpointId,ServiceName,VpcEndpointType,State]' --output text

echo
echo "MATRIX COMPLETE"
} 2>&1 | tee "$PROOF/02_connectivity_matrix.txt"

echo "==> Wrote $PROOF/02_connectivity_matrix.txt"
