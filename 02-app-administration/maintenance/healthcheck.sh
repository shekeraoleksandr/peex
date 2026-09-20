#!/usr/bin/env bash
# Health check for peex-web. Exit 0 = healthy, non-zero = unhealthy.
# Also exports a Prometheus textfile metric for monitoring integration.
set -uo pipefail
SERVICE_NAME="peex-web"
PORT=8080
METRIC_DIR="/var/lib/peex-web/metrics"
# If a node_exporter textfile collector dir exists, publish there too.
NODE_TEXTFILE="/var/lib/node_exporter/textfile_collector"
ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }
log() { printf '%s [healthcheck] %s\n' "$(ts)" "$*"; }

rc=0
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "systemd: $SERVICE_NAME is active"
else
    log "systemd: $SERVICE_NAME is NOT active"; rc=1
fi

if curl -fsS "http://127.0.0.1:${PORT}/healthz" 2>/dev/null | grep -q ok; then
    log "http: /healthz returned ok"
else
    log "http: /healthz check FAILED"; rc=1
fi

if ss -ltn 2>/dev/null | grep -q ":${PORT} "; then
    log "port: ${PORT} is listening"
else
    log "port: ${PORT} is NOT listening"; rc=1
fi

# Publish metric (1 = up, 0 = down) for monitoring integration
metric="peex_web_up ${rc:+0}"; [ "$rc" -eq 0 ] && metric="peex_web_up 1"
mkdir -p "$METRIC_DIR" 2>/dev/null || true
printf '# HELP peex_web_up Service health (1=up,0=down)\n# TYPE peex_web_up gauge\n%s\n' "$metric" \
    > "$METRIC_DIR/peex-web.prom" 2>/dev/null || true
if [ -d "$NODE_TEXTFILE" ]; then
    cp -f "$METRIC_DIR/peex-web.prom" "$NODE_TEXTFILE/peex-web.prom" 2>/dev/null || true
    log "metric: published to node_exporter textfile collector"
fi

[ "$rc" -eq 0 ] && log "RESULT: HEALTHY" || log "RESULT: UNHEALTHY"
exit "$rc"
