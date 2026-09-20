#!/usr/bin/env bash
# Deploy the container-observability stack onto the monitoring EC2 instance
# created by 11-network. Replaces the minimal Prometheus+Grafana that the
# instance's cloud-init installed.
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require ssh
require scp
load_targets

echo "==> monitoring instance: $MON_IP"
echo "==> web instance (scrape target, private): $WEB_PRIVATE_IP"

# ---------------------------------------------------------------------------
# Preflight. This stack is nine containers on a t3.micro (2 vCPU, 1 GiB RAM,
# 8 GiB root). Both of the things that can sink it are checkable in advance,
# and both are much cheaper to catch here than halfway through a demo.
# ---------------------------------------------------------------------------
echo "==> Preflight on $MON_IP"

echo "--- memory / disk before ---"
rsh "free -m | head -2; echo; df -h / | tail -1"

# 1) RAM. Prometheus + Grafana + Loki alone will approach 1 GiB, and Ubuntu
#    images ship with no swap, so the kernel OOM-kills whichever container
#    happens to allocate next -- usually Prometheus, mid-scrape, which looks
#    like a mysterious restart loop rather than an out-of-memory condition.
#    A swapfile is not a substitute for RAM, but it is the difference between
#    "slow" and "the stack keeps dying".
echo
echo "==> Ensuring a 2G swapfile exists (t3.micro has 1 GiB RAM and no swap)"
rsh "
  set -e
  if [ -f /swapfile ] && swapon --show | grep -q /swapfile; then
      echo 'swap already active'
  else
      sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
      sudo chmod 600 /swapfile
      sudo mkswap /swapfile >/dev/null
      sudo swapon /swapfile
      grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
      echo 'swap enabled'
  fi
  swapon --show
"

# 2) The compose plugin. cloud-init tried two different package names for it
#    and was allowed to fail -- it had a `docker run` fallback. This script has
#    no such fallback, so if the plugin is genuinely missing, say so here
#    rather than dying on an unhelpful "docker: 'compose' is not a command".
echo
echo "==> Checking for the docker compose plugin"
if ! rsh "sudo docker compose version" >/dev/null 2>&1; then
    echo "    not present -- attempting to install it"
    rsh "sudo apt-get update -y >/dev/null 2>&1
         sudo apt-get install -y docker-compose-v2 >/dev/null 2>&1 \
           || sudo apt-get install -y docker-compose-plugin >/dev/null 2>&1 \
           || true" || true
    if ! rsh "sudo docker compose version" >/dev/null 2>&1; then
        echo
        echo "ERROR: the monitoring instance has no 'docker compose' plugin and it" >&2
        echo "       could not be installed (check the instance's egress / apt)." >&2
        echo "       Install it by hand, then re-run this script:" >&2
        echo "         ssh -i \"$KEY\" ubuntu@$MON_IP" >&2
        echo "         sudo apt-get install -y docker-compose-v2" >&2
        exit 1
    fi
fi
rsh "sudo docker compose version"

echo
echo "==> Copying stack to $MON_IP:~/$REMOTE_DIR"
rsh "mkdir -p ~/$REMOTE_DIR"
scp -q -r "${SSH_OPTS[@]}" \
    "$ROOT/docker-compose.yml" \
    "$ROOT/prometheus" "$ROOT/alertmanager" "$ROOT/blackbox" \
    "$ROOT/loki" "$ROOT/promtail" "$ROOT/grafana" "$ROOT/webhook" \
    "ubuntu@$MON_IP:~/$REMOTE_DIR/"

echo "==> Templating the web instance's private IP into prometheus.yml"
rsh "sed -i 's/__WEB_PRIVATE_IP__/$WEB_PRIVATE_IP/g' ~/$REMOTE_DIR/prometheus/prometheus.yml && grep -n '$WEB_PRIVATE_IP' ~/$REMOTE_DIR/prometheus/prometheus.yml"

echo "==> Stopping the minimal stack cloud-init installed (if present)"
rsh "sudo docker rm -f prometheus grafana 2>/dev/null || true"

echo "==> Starting the full stack"
rsh "cd ~/$REMOTE_DIR && sudo docker compose up -d"

# A fixed `sleep 20` is a guess. Poll the readiness endpoint instead, so the
# script reports what actually happened rather than assuming it worked.
echo "==> Waiting for Prometheus to become ready (up to 120s)"
ready=""
for i in $(seq 1 24); do
    if rsh "curl -fsS -m 5 localhost:9090/-/ready" >/dev/null 2>&1; then
        ready=1; echo "    ready after $((i * 5))s"; break
    fi
    sleep 5
done
[ -n "$ready" ] || echo "    WARN: Prometheus not ready after 120s -- see the container states below"

echo
rsh "cd ~/$REMOTE_DIR && sudo docker compose ps" || true

# Nine containers, and a partial start is the failure mode that quietly ruins
# the proof run: everything looks deployed, but cAdvisor died and the whole
# per-container metrics section comes back empty.
echo
echo "==> Container states (anything not Up is a problem)"
rsh "sudo docker ps -a --filter 'name=peex_' --format '{{.Names}}\t{{.Status}}'" || true

echo
echo "--- memory / disk after ---"
rsh "free -m | head -2; echo; df -h / | tail -1" || true

echo
echo "==> Any container killed for running out of memory?"
rsh "sudo dmesg -T 2>/dev/null | grep -i -m5 'killed process' || echo '  (no OOM kills in dmesg -- good)'" || true

echo
echo "==> Done."
echo "    Grafana:      http://$MON_IP:3000   (admin / peexdemo123)"
echo "    Prometheus:   http://$MON_IP:9090"
echo
echo "    Alertmanager / cAdvisor / Loki are NOT exposed to the internet by"
echo "    design. Reach them over an SSH tunnel:"
echo "      ssh -i \"$KEY\" -L 9093:localhost:9093 -L 8081:localhost:8080 -L 3100:localhost:3100 ubuntu@$MON_IP"
echo "      then open http://localhost:9093 (Alertmanager) and http://localhost:8081 (cAdvisor)"
