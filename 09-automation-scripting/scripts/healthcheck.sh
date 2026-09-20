#!/usr/bin/env bash
# healthcheck.sh — routine DevOps task: check a list of HTTP endpoints and
# report status. Exits non-zero if any endpoint is unhealthy.
set -uo pipefail
export LOG_TAG=healthcheck
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/common.sh
source "$HERE/../lib/common.sh"

FILE="$HERE/endpoints.sample.txt"
TIMEOUT=5

usage() {
    cat <<EOF
Usage: healthcheck.sh [--file endpoints.txt] [--timeout SECONDS]
  --file FILE      one URL per line (default: endpoints.sample.txt)
  --timeout N      per-request timeout in seconds (default: $TIMEOUT)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --file) FILE="${2:?}"; shift ;;
        --timeout) TIMEOUT="${2:?}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done
require_cmd curl
[ -f "$FILE" ] || die "endpoints file not found: $FILE"

fail=0; total=0
printf '%-40s %-6s %s\n' "ENDPOINT" "CODE" "RESULT"
printf '%-40s %-6s %s\n' "----------------------------------------" "------" "------"
while IFS= read -r url; do
    case "$url" in ''|\#*) continue ;; esac
    total=$((total+1))
    code="$(curl -s -o /dev/null -m "$TIMEOUT" -w '%{http_code}' "$url" 2>/dev/null)"
    code="${code:-000}"
    if [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
        printf '%-40s %-6s %s\n' "$url" "$code" "OK"
    else
        printf '%-40s %-6s %s\n' "$url" "$code" "FAIL"; fail=$((fail+1))
    fi
done < "$FILE"

echo
log "checked $total endpoint(s), $fail unhealthy"
[ "$fail" -eq 0 ] || exit 1
