#!/usr/bin/env bash
# Verify firewall rules against a provided baseline (Trainee).
# Reads the ACTIVE ruleset (or a captured file passed as $2) and checks that
# each required baseline pattern is present. Produces a documented result table.
# Usage:
#   sudo ./verify-firewall.sh [baseline] [rules-file]
#   ./verify-firewall.sh firewall-baseline.txt sample-rules.txt   # offline demo
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BASELINE="${1:-$HERE/firewall-baseline.txt}"
RULES_FILE="${2:-}"

echo "=============================================================="
echo " Firewall baseline verification  —  $(date -u '+%F %T UTC')"
echo " Baseline: $BASELINE"
echo "=============================================================="

# 1. Obtain the active ruleset (or use a provided capture)
if [ -n "$RULES_FILE" ]; then
    SRC="file: $RULES_FILE"
    RULES="$(cat "$RULES_FILE")"
elif command -v iptables >/dev/null 2>&1 && iptables -L -n >/dev/null 2>&1; then
    SRC="iptables -L -n"; RULES="$(iptables -L -n)"
elif command -v ufw >/dev/null 2>&1; then
    SRC="ufw status verbose"; RULES="$(ufw status verbose)"
elif command -v nft >/dev/null 2>&1; then
    SRC="nft list ruleset"; RULES="$(nft list ruleset)"
else
    echo "No firewall tool available and no rules file provided." >&2; exit 2
fi
echo "Active ruleset source: $SRC"
echo
echo "----- current ruleset -----"
echo "$RULES"
echo "---------------------------"
echo

# 2. Compare each required baseline pattern
echo "Result (required rule -> status):"
printf '%-22s %-10s %s\n' "PATTERN" "STATUS" "DESCRIPTION"
printf '%-22s %-10s %s\n' "----------------------" "----------" "-----------"
missing=0
while IFS= read -r line; do
    line="${line%%$'\r'}"
    case "$line" in ''|\#*) continue;; esac
    pat="$(echo "$line" | sed 's/#.*//' | xargs)"
    desc="$(echo "$line" | grep -o '#.*' | sed 's/^#\s*//')"
    [ -z "$pat" ] && continue
    if grep -qF "$pat" <<<"$RULES"; then
        status="PRESENT"
    else
        status="MISSING"; missing=$((missing+1))
    fi
    printf '%-22s %-10s %s\n' "$pat" "$status" "$desc"
done < "$BASELINE"

echo
if [ "$missing" -eq 0 ]; then
    echo "PASS: all required rules present."
else
    echo "REVIEW NEEDED: $missing required rule(s) MISSING — flag to security owner."
fi
exit $(( missing > 0 ? 1 : 0 ))
