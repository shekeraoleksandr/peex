#!/usr/bin/env bash
# Roll back the PeEx web content to the previous (or a specified) backup.
set -euo pipefail
SERVICE_NAME="peex-web"
BACKUP_DIR="/var/lib/peex-web/backups"
LOG="/var/log/peex-web/maintenance.log"
HERE="$(cd "$(dirname "$0")" && pwd)"

log() { printf '%s [rollback] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }
die() { printf '%s [rollback][ERROR] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must run as root (use sudo)"

archive="${1:-}"
if [ -z "$archive" ]; then
    archive="$(ls -1t "$BACKUP_DIR"/peex-web-*.tgz 2>/dev/null | head -1 || true)"
fi
[ -n "$archive" ] && [ -f "$archive" ] || die "no backup archive found in $BACKUP_DIR"

log "Restoring from $archive"
tar xzf "$archive" -C /
systemctl reload "$SERVICE_NAME" || systemctl restart "$SERVICE_NAME"

log "Post-rollback smoke test"
if "$HERE/smoke_test.sh"; then
    log "SUCCESS: rolled back using $(basename "$archive")"
else
    die "smoke test failed after rollback"
fi
