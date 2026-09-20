#!/usr/bin/env bash
# Apply/observe observability practices on the containerized app (Middle):
# health status, resource usage, structured logs, and metrics endpoint.
set -uo pipefail
NAME=peex_app

echo "== Container health & status =="
docker ps --filter "name=$NAME" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
echo "health: $(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$NAME" 2>/dev/null)"

echo
echo "== Resource usage (docker stats snapshot) =="
docker stats --no-stream "$NAME"

echo
echo "== Structured JSON logs (last 10) =="
docker logs --tail 10 "$NAME"

echo
echo "== Metrics endpoint (Prometheus format) =="
curl -s http://127.0.0.1:8080/metrics

echo
echo "== Liveness probe =="
curl -s -w "  (/healthz -> %{http_code})\n" http://127.0.0.1:8080/healthz
