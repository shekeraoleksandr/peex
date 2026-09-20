#!/usr/bin/env bash
# Capture the steady-state observability evidence: components running, metrics
# actually arriving, logs aggregated, alert rules loaded, example queries.
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_targets

{
echo "### CONTAINER OBSERVABILITY PROOF @ $(date -u '+%F %T UTC')"
echo "monitoring instance: $MON_IP   web instance (private): $WEB_PRIVATE_IP"

echo
echo "===== 1. Monitoring components deployed ====="
note "sudo docker compose ps"
rsh "cd ~/$REMOTE_DIR && sudo docker compose ps" || echo "(could not list the stack -- is it deployed?)"

echo
echo "===== 2. Prometheus scrape targets (container + host + probe sources) ====="
note "curl -s localhost:9090/api/v1/targets | summary"
rsh "curl -s -m 15 localhost:9090/api/v1/targets" | python3 -c "
import json,sys
raw=sys.stdin.read().strip()
if not raw: print('  (no response from Prometheus -- is the stack up?)'); raise SystemExit
try: d=json.loads(raw)
except Exception: print('  (unparseable response)'); raise SystemExit
ts=d.get('data',{}).get('activeTargets',[])
if not ts: print('  (Prometheus has no active targets at all)'); raise SystemExit
for t in ts:
    print(f\"  {t['labels'].get('job','?'):18s} {t['labels'].get('instance','?'):32s} {t['health']}\")
" 2>/dev/null || true

echo
echo "===== 3. CONTAINER metrics are being collected (cAdvisor) ====="
note "# per-container CPU, top 10"
promq 'topk(10, sum by (name) (rate(container_cpu_usage_seconds_total{name!=""}[2m])))' 1 ' cores'

note "# per-container memory, top 10"
promq 'topk(10, sum by (name) (container_memory_usage_bytes{name!=""}))' 0.00000095367431640625 ' MiB'

note "# per-container network receive rate"
promq 'topk(5, sum by (name) (rate(container_network_receive_bytes_total{name!=""}[2m])))' 1 ' B/s'

echo
echo "===== 4. Application-level signals (HTTP availability + latency) ====="
note "# probe_success / probe_duration_seconds per endpoint"
promq 'probe_success' 1 ' (1=up)'
promq 'probe_duration_seconds' 1 ' s'

echo
echo "===== 5. Centralized logging (Loki + Promtail) ====="
note "curl -s localhost:3100/loki/api/v1/labels"
rsh "curl -s localhost:3100/loki/api/v1/labels" || true
note "# which containers are shipping logs"
rsh "curl -s 'localhost:3100/loki/api/v1/label/container/values'" || true
note "# a real log query"
rsh "curl -sG localhost:3100/loki/api/v1/query_range --data-urlencode 'query={environment=\"aws-ec2\"}' --data-urlencode 'limit=5'" | head -c 1500 || true

echo
echo
echo "===== 6. Alert rules loaded, with thresholds ====="
note "curl -s localhost:9090/api/v1/rules | rule summary"
rsh "curl -s -m 15 localhost:9090/api/v1/rules" | python3 -c "
import json,sys
raw=sys.stdin.read().strip()
if not raw: print('  (no response from Prometheus)'); raise SystemExit
d=json.loads(raw)
gs=d.get('data',{}).get('groups',[])
if not gs: print('  (Prometheus loaded NO rule groups -- alert.rules.yml was not picked up)'); raise SystemExit
for g in gs:
    print(f\"  group: {g['name']}\")
    for r in g.get('rules',[]):
        print(f\"    - {r.get('name','?'):24s} state={r.get('state','-'):8s} for={r.get('duration','-')}\")
        print(f\"        expr: {r.get('query','')[:110]}\")
" 2>/dev/null || true

echo
echo "===== 7. Alertmanager: routing, inhibition, receivers ====="
note "curl -s localhost:9093/api/v2/status | config"
rsh "curl -s localhost:9093/api/v2/status" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('config',{}).get('original','(no config returned)'))
" 2>/dev/null || true

echo
echo "===== 8. Monitoring overhead (must stay modest on a t3.micro) ====="
note "sudo docker stats --no-stream"
rsh "sudo docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'" || true

echo
echo "===== 9. Retention settings (cost / disk control) ====="
note "# Prometheus retention flags"
rsh "sudo docker inspect peex_prometheus --format '{{json .Config.Cmd}}'" || true
note "# Loki retention"
rsh "grep -A3 retention ~/$REMOTE_DIR/loki/loki-config.yml" || true

echo
echo "PROOF DONE"
} 2>&1 | tee "$PROOF/01_observability_proof.txt"

echo "==> Wrote $PROOF/01_observability_proof.txt"
