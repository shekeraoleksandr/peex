#!/usr/bin/env bash
# Remove the PeEx demo web service. Keeps nginx package by default.
set -euo pipefail
SERVICE_NAME="peex-web"
[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl daemon-reload
rm -rf /etc/peex-web /var/www/peex-web /opt/peex-web \
       /var/log/peex-web /var/lib/peex-web /run/peex-web
userdel peexweb 2>/dev/null || true
echo "[uninstall] done"
