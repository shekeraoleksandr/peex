#!/usr/bin/env bash
# Run this on the cloud VM AFTER install.sh to capture every acceptance-
# criteria artifact into ./proof/. Re-run after a reboot to prove auto-start.
set -uo pipefail
SERVICE_NAME="peex-web"
SERVICE_USER="peexweb"
PORT=8080
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/proof"
mkdir -p "$OUT"
run() { echo "\$ $*"; "$@" 2>&1; echo; }

{
  echo "# PeEx proof — $(date)"; echo "# host: $(uname -a)"; echo
  echo "===== Dedicated service user ====="
  run getent passwd "$SERVICE_USER"
  run id "$SERVICE_USER"
  echo "===== Customized configuration ====="
  run cat /etc/peex-web/nginx-peex.conf
  echo "===== systemd unit ====="
  run systemctl cat "$SERVICE_NAME"
  echo "===== Service status ====="
  run systemctl status "$SERVICE_NAME" --no-pager
  echo "===== Auto-start enabled ====="
  run systemctl is-enabled "$SERVICE_NAME"
  echo "===== Running under the correct user ====="
  run bash -c "ps -o user,pid,ppid,cmd -C nginx"
  echo "===== Listening port ====="
  run bash -c "ss -ltnp | grep ':${PORT} ' || ss -ltn | grep ':${PORT} '"
  echo "===== Health / content ====="
  run curl -i "http://127.0.0.1:${PORT}/healthz"
  run curl -i "http://127.0.0.1:${PORT}/"
  echo "===== Recent logs (healthy operation) ====="
  run bash -c "journalctl -u ${SERVICE_NAME} --no-pager | tail -n 20"
  run bash -c "tail -n 10 /var/log/peex-web/error.log 2>/dev/null || echo '(no error log yet)'"
} | tee "$OUT/00_deploy_proof.txt"

echo "==> Wrote $OUT/00_deploy_proof.txt"
echo "==> For reboot proof: 'sudo reboot', then re-run this script -> 01_after_reboot.txt"
if [ -f "$OUT/00_deploy_proof.txt" ] && [ -n "${REBOOT_PROOF:-}" ]; then
  cp "$OUT/00_deploy_proof.txt" "$OUT/01_after_reboot.txt"
fi
exit 0
