#!/usr/bin/env bash
# Deploy & configure the PeEx demo web service at the OS level.
# Idempotent: safe to run repeatedly and on a clean VM.
set -euo pipefail

SERVICE_USER="peexweb"
SERVICE_NAME="peex-web"
PORT=8080
CONF_DIR="/etc/peex-web"
DOCROOT="/var/www/peex-web"
APP_DIR="/opt/peex-web"
UNIT_DST="/etc/systemd/system/${SERVICE_NAME}.service"
VERSION="1.0.0"
HERE="$(cd "$(dirname "$0")" && pwd)"

log() { printf '[install] %s\n' "$*"; }
die() { printf '[install][ERROR] %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must run as root (use sudo)"

log "1/8 Checking dependencies"
command -v systemctl >/dev/null || die "systemd (systemctl) is required"
command -v curl      >/dev/null || apt-get install -y -qq curl

log "2/8 Installing nginx from official apt repository"
if ! command -v nginx >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq nginx
fi
# We run our OWN unit; make sure the packaged service is not competing.
systemctl disable --now nginx >/dev/null 2>&1 || true

log "3/8 Creating dedicated non-login service user '${SERVICE_USER}'"
if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
fi

log "4/8 Creating directories with least-privilege ownership"
install -d -m 0755 "$CONF_DIR" "$APP_DIR"
install -d -m 0755 -o "$SERVICE_USER" -g "$SERVICE_USER" /var/log/peex-web
install -d -m 0755 -o "$SERVICE_USER" -g "$SERVICE_USER" /var/lib/peex-web /var/lib/peex-web/tmp /var/lib/peex-web/backups /var/lib/peex-web/metrics
install -d -m 0755 -o "$SERVICE_USER" -g "$SERVICE_USER" /run/peex-web
install -d -m 0755 "$DOCROOT"

log "5/8 Deploying customized configuration and web content"
install -m 0644 "$HERE/config/nginx-peex.conf" "$CONF_DIR/nginx-peex.conf"
cp -f "$HERE/README.md" "$APP_DIR/README.md" 2>/dev/null || true
printf '%s\n' "$VERSION" > "$DOCROOT/VERSION"
cat > "$DOCROOT/index.html" <<HTML
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>PeEx Web Service</title></head>
<body style="font-family:sans-serif;max-width:40rem;margin:3rem auto">
<h1>PeEx demo web service</h1>
<p>Deployed and configured at the OS level, managed by the systemd unit
<code>${SERVICE_NAME}.service</code>, running as the unprivileged user
<code>${SERVICE_USER}</code> on port <strong>${PORT}</strong>.</p>
<p>Version: <strong>${VERSION}</strong></p>
</body></html>
HTML

log "6/8 Installing systemd unit"
install -m 0644 "$HERE/config/peex-web.service" "$UNIT_DST"
systemctl daemon-reload

log "7/8 Validating nginx configuration"
nginx -t -c "$CONF_DIR/nginx-peex.conf"

# Fix ownership: the root-run "nginx -t" above can create root-owned log
# files; ensure the service user owns its writable dirs (also cleans up
# stale root-owned files from a previous failed start).
chown -R "$SERVICE_USER:$SERVICE_USER" /var/log/peex-web /var/lib/peex-web /run/peex-web 2>/dev/null || true

log "8/8 Enabling and (re)starting the service"
systemctl enable "$SERVICE_NAME" >/dev/null
systemctl restart "$SERVICE_NAME"

sleep 1
if systemctl is-active --quiet "$SERVICE_NAME" \
   && curl -fsS "http://127.0.0.1:${PORT}/healthz" | grep -q ok; then
    log "SUCCESS: ${SERVICE_NAME} is active and healthy on port ${PORT}"
else
    systemctl status "$SERVICE_NAME" --no-pager || true
    die "service did not come up healthy"
fi
