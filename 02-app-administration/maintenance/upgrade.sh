#!/usr/bin/env bash
# Upgrade the PeEx web content to a new version with dependency checks,
# backup, reload and post-upgrade smoke test (auto-rollback on failure).
# Idempotent: re-running with the same version is a no-op.
set -euo pipefail
SERVICE_NAME="peex-web"
DOCROOT="/var/www/peex-web"
CONF_DIR="/etc/peex-web"
BACKUP_DIR="/var/lib/peex-web/backups"
LOG="/var/log/peex-web/maintenance.log"
HERE="$(cd "$(dirname "$0")" && pwd)"

log() { printf '%s [upgrade] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }
die() { printf '%s [upgrade][ERROR] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must run as root (use sudo)"
mkdir -p "$BACKUP_DIR" "$(dirname "$LOG")"

log "Dependency checks"
for dep in nginx systemctl curl tar; do command -v "$dep" >/dev/null || die "missing dependency: $dep"; done
systemctl cat "$SERVICE_NAME" >/dev/null 2>&1 || die "$SERVICE_NAME is not installed; run install.sh first"

cur="$(cat "$DOCROOT/VERSION" 2>/dev/null || echo 0.0.0)"
new="${1:-}"
if [ -z "$new" ]; then
    IFS=. read -r a b c <<<"$cur"; new="${a}.${b}.$(( ${c:-0} + 1 ))"
fi
log "Current version: $cur  ->  target version: $new"
if [ "$new" = "$cur" ]; then log "Already at version $new; nothing to do"; exit 0; fi

ts="$(date '+%Y%m%d-%H%M%S')"
backup="$BACKUP_DIR/peex-web-${cur}-${ts}.tgz"
log "Backing up current state to $backup"
tar czf "$backup" "$CONF_DIR" "$DOCROOT" 2>/dev/null
nginx -v 2>>"$LOG" || true

log "Deploying new content (version $new)"
printf '%s\n' "$new" > "$DOCROOT/VERSION"
cat > "$DOCROOT/index.html" <<HTML
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>PeEx Web Service</title></head>
<body style="font-family:sans-serif;max-width:40rem;margin:3rem auto">
<h1>PeEx demo web service</h1>
<p>Managed by <code>${SERVICE_NAME}.service</code> (user <code>peexweb</code>).</p>
<p>Version: <strong>${new}</strong> (upgraded ${ts})</p>
</body></html>
HTML

log "Reloading service"
systemctl reload "$SERVICE_NAME" || systemctl restart "$SERVICE_NAME"

log "Post-upgrade smoke test"
if "$HERE/smoke_test.sh"; then
    log "SUCCESS: upgraded to $new and smoke test passed"
else
    log "Smoke test FAILED — rolling back automatically"
    tar xzf "$backup" -C /
    systemctl reload "$SERVICE_NAME" || systemctl restart "$SERVICE_NAME"
    die "upgrade rolled back to $cur"
fi
