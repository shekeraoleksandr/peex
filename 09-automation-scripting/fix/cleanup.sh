#!/usr/bin/env bash
# log-cleanup (FIXED) — delete log files OLDER than N days.
set -euo pipefail
DIR="${1:?usage: cleanup.sh DIR DAYS}"
DAYS="${2:?usage: cleanup.sh DIR DAYS}"

# FIX: '-mtime +N' matches files last modified MORE than N days ago (old ones).
find "$DIR" -type f -name '*.log' -mtime +"$DAYS" -print -delete
