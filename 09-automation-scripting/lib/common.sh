# Shared helpers for the automation scripts (source this file).
# shellcheck shell=bash

log()  { printf '%s [%s] %s\n' "$(date '+%F %T')" "${LOG_TAG:-script}" "$*"; }
warn() { printf '%s [%s] WARN: %s\n' "$(date '+%F %T')" "${LOG_TAG:-script}" "$*" >&2; }
die()  { printf '%s [%s] ERROR: %s\n' "$(date '+%F %T')" "${LOG_TAG:-script}" "$*" >&2; exit 1; }

require_cmd() {
    local c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || die "required command not found: $c"
    done
}
