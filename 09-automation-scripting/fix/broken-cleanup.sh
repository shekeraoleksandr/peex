#!/usr/bin/env bash
# log-cleanup — intended to delete log files OLDER than N days.
# NOTE: this version contains a BUG (see fix/BUGFIX.md).
set -euo pipefail
DIR="${1:?usage: broken-cleanup.sh DIR DAYS}"
DAYS="${2:?usage: broken-cleanup.sh DIR DAYS}"

# BUG: '-mtime -N' matches files modified WITHIN the last N days (recent ones),
# so this deletes the WRONG files (it should be '+N' for older-than-N).
find "$DIR" -type f -name '*.log' -mtime -"$DAYS" -print -delete
