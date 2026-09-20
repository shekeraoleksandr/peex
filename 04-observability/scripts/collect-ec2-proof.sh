#!/usr/bin/env bash
# Extra proof for "Configure infrastructure monitoring and logging" (Junior,
# KEY): the SAME Prometheus/Grafana stack, but hosted on a real EC2 instance
# (../11-network/) instead of local Docker, scraping another real EC2's
# node_exporter over the private VPC IP. Run ../11-network/scripts/apply.sh
# FIRST, then run this. This is IN ADDITION to the local docker-compose stack
# below (which still covers the Trainee log/alerting items) -- it is not a
# replacement.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TFDIR="$HERE/../../11-network/terraform"
PROOF="$HERE/../proof"
mkdir -p "$PROOF"

cd "$TFDIR"
MON_IP="$(terraform output -raw monitoring_public_ip)"
WEB_PRIVATE_IP="$(terraform output -raw web_private_ip)"
KEY="$(terraform output -raw ssh_key_path)"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -i "$KEY")

{
echo "### INFRASTRUCTURE MONITORING PROOF (real EC2) @ $(date -u '+%F %T UTC')"
echo "monitoring=$MON_IP  scraping web-instance private ip=$WEB_PRIVATE_IP:9100"
echo

echo "===== containers running on the monitoring instance ====="
ssh "${SSH_OPTS[@]}" "ubuntu@$MON_IP" '
  sudo docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
  echo "-- the compose file that defines the stack --"
  cat /opt/peex-monitoring/docker-compose.yml
'

echo
echo "===== Prometheus targets (web-instance should be UP) ====="
curl -sS "http://$MON_IP:9090/api/v1/targets" | python3 -m json.tool 2>/dev/null || curl -sS "http://$MON_IP:9090/api/v1/targets"

echo
echo "===== A real metric, scraped live from the web instance ====="
curl -sS "http://$MON_IP:9090/api/v1/query?query=node_load1" | python3 -m json.tool 2>/dev/null || true

echo
echo "===== Grafana health + datasource ====="
curl -sS "http://$MON_IP:3000/api/health"; echo

echo
echo "DONE"
} 2>&1 | tee "$PROOF/02_ec2_infrastructure_monitoring.txt"
echo "==> Wrote $PROOF/02_ec2_infrastructure_monitoring.txt"
echo "==> Grafana: http://$MON_IP:3000  (admin / peexdemo123)"
