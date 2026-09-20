#!/usr/bin/env bash
# Deliberately fire a real alert so the "triggered alert + notification"
# artifact is genuine rather than a screenshot of a green dashboard.
#
# Two independent alert paths are exercised:
#   1. CPU load in a container   -> Prometheus rule -> Alertmanager -> webhook
#   2. Killing a container       -> ContainerDisappeared / TargetDown
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_targets

MODE="${1:-stress}"
DURATION="${DURATION:-180}"

case "$MODE" in
  stress)
    echo "==> Starting a CPU-burning container (peex_stress) for ${DURATION}s"
    echo "    This trips DemoStressAlert (>0.2 cores for 30s) and, if it runs"
    echo "    long enough, ContainerHighCpu."
    # Self-limiting: the hog stops itself after DURATION even if the cleanup
    # prompt at the end is declined, so a forgotten "n" cannot leave a CPU
    # burning on the instance. It also means the alert RESOLVES on its own,
    # which puts a resolved-notification in the webhook log -- the other half
    # of the trigger -> notify chain, and better evidence than a firing alert
    # alone.
    rsh "sudo docker rm -f peex_stress 2>/dev/null || true
         sudo docker run -d --name peex_stress --cpus=1 alpine:3.20 \
           sh -c 'timeout $DURATION sh -c \"while :; do :; done\"'"
    echo "==> Container started. Waiting ~90s for the rule to fire..."
    sleep 90
    ;;
  kill)
    echo "==> Killing the blackbox container to trip ContainerDisappeared/TargetDown"
    rsh "sudo docker stop peex_blackbox"
    echo "==> Waiting ~150s (ContainerDisappeared needs >60s stale + 1m for)..."
    sleep 150
    ;;
  *)
    echo "usage: $0 [stress|kill]"; exit 2 ;;
esac

{
echo "### TRIGGERED ALERT PROOF ($MODE) @ $(date -u '+%F %T UTC')"

note "curl -s localhost:9090/api/v1/alerts   # what Prometheus considers firing"
rsh "curl -s localhost:9090/api/v1/alerts" | python3 -m json.tool 2>/dev/null || true

note "curl -s localhost:9093/api/v2/alerts   # what Alertmanager received"
rsh "curl -s localhost:9093/api/v2/alerts" | python3 -m json.tool 2>/dev/null || true

note "curl -s localhost:5001/alerts   # what the automated process recorded"
rsh "curl -s localhost:5001/alerts" || true

note "sudo docker logs --tail 20 peex_webhook_sink   # the triggered action"
rsh "sudo docker logs --tail 20 peex_webhook_sink" 2>&1 || true
} 2>&1 | tee "$PROOF/03_triggered_alert_${MODE}.txt"

echo
echo "==> Wrote $PROOF/03_triggered_alert_${MODE}.txt"
echo "==> Screenshot now: Alertmanager over the tunnel (http://localhost:9093)"
echo "    and Grafana's 'Firing alerts' panel (http://$MON_IP:3000)."
echo
read -r -p "Clean up the trigger (stop stress / restart blackbox)? [Y/n] " ans
if [ "${ans:-Y}" != "n" ] && [ "${ans:-Y}" != "N" ]; then
    case "$MODE" in
      stress) rsh "sudo docker rm -f peex_stress" ;;
      kill)   rsh "sudo docker start peex_blackbox" ;;
    esac
    echo "==> Cleaned up. Alerts should resolve within a few minutes"
    echo "    (watch for the 'resolved' entry in the webhook log)."
fi
