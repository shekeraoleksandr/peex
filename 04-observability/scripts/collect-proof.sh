#!/usr/bin/env bash
# Run AFTER `docker compose up -d` (give it ~30s to settle) to capture
# observability evidence into ../proof/observability_proof.txt.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/proof"; mkdir -p "$OUT"
P="http://localhost:9090"; A="http://localhost:9093"; L="http://localhost:3100"; G="http://localhost:3000"
run() { echo "\$ $*"; eval "$*" 2>&1; echo; }

{
echo "# Observability proof — $(date -u '+%F %T UTC')"
echo

echo "===== [Junior KEY] Monitoring: Prometheus targets ====="
run "curl -s $P/api/v1/targets | python3 -m json.tool | grep -E '\"(job|health|scrapeUrl)\"'"

echo "===== Sample metric query: up (1 = target healthy) ====="
run "curl -s '$P/api/v1/query?query=up' | python3 -m json.tool"

echo "===== Infra metric: node_load1 ====="
run "curl -s '$P/api/v1/query?query=node_load1' | python3 -m json.tool"

echo "===== [Junior KEY] Logging: Loki labels (ingesting logs) ====="
run "curl -s $L/loki/api/v1/labels"
run "curl -s --get $L/loki/api/v1/query_range --data-urlencode 'query={job=\"varlogs\"}' --data-urlencode 'limit=5' | python3 -m json.tool | head -40"

echo "===== Dashboards: Grafana health ====="
run "curl -s $G/api/health"

echo "===== [Trainee] Trigger: alert rules loaded ====="
run "curl -s $P/api/v1/rules | python3 -m json.tool | grep -E '\"(name|state|type)\"'"

echo "===== [Trainee] Fire a TEST alert -> Alertmanager -> automated process ====="
run "curl -s -XPOST $A/api/v2/alerts -H 'Content-Type: application/json' -d '[{\"labels\":{\"alertname\":\"PeexTestTrigger\",\"severity\":\"critical\",\"instance\":\"demo\"},\"annotations\":{\"summary\":\"manual test trigger\"}}]' && echo posted"
echo "(waiting for group_wait...)"; sleep 12
echo "-- webhook-sink recorded the triggered action: --"
run "docker exec peex_webhook_sink cat /data/alerts.log 2>/dev/null || docker compose -f $ROOT/docker-compose.yml logs --no-color webhook-sink | tail -n 15"

echo "# DONE"
} | tee "$OUT/observability_proof.txt"
echo "wrote $OUT/observability_proof.txt"
