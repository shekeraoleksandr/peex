#!/usr/bin/env bash
# backup.sh — routine DevOps task: create a timestamped tar.gz backup of a
# directory and prune old backups (retention). Supports --dry-run.
set -euo pipefail
export LOG_TAG=backup
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/common.sh
source "$HERE/../lib/common.sh"

RETENTION=5
DRY_RUN=0

usage() {
    cat <<EOF
Usage: backup.sh SRC_DIR DEST_DIR [--retention N] [--dry-run]
  SRC_DIR       directory to back up
  DEST_DIR      where to store backup-*.tar.gz
  --retention N keep the N most recent backups (default: $RETENTION)
  --dry-run     show what would happen without changing anything
EOF
}

ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --retention) RETENTION="${2:?}"; shift ;;
        --dry-run)   DRY_RUN=1 ;;
        -h|--help)   usage; exit 0 ;;
        -*)          die "unknown option: $1" ;;
        *)           ARGS+=("$1") ;;
    esac
    shift
done
[ "${#ARGS[@]}" -eq 2 ] || { usage; die "SRC_DIR and DEST_DIR are required"; }
SRC="${ARGS[0]}"; DEST="${ARGS[1]}"
require_cmd tar
[ -d "$SRC" ] || die "source directory does not exist: $SRC"

ts="$(date '+%Y%m%d-%H%M%S')"
archive="$DEST/backup-${ts}.tar.gz"

if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] would create $archive from $SRC"
else
    mkdir -p "$DEST"
    tar -czf "$archive" -C "$(dirname "$SRC")" "$(basename "$SRC")"
    log "created $archive ($(wc -c < "$archive") bytes)"
fi

# Retention: keep the N most recent, prune the rest
mapfile -t backups < <(ls -1t "$DEST"/backup-*.tar.gz 2>/dev/null || true)
if [ "${#backups[@]}" -gt "$RETENTION" ]; then
    for old in "${backups[@]:$RETENTION}"; do
        if [ "$DRY_RUN" -eq 1 ]; then
            log "[dry-run] would prune $old"
        else
            rm -f "$old"; log "pruned $old"
        fi
    done
else
    log "retention OK (${#backups[@]} backups, keeping $RETENTION)"
fi
