#!/usr/bin/env bash
# Extract and summarize log entries (Trainee item).
# Usage: ./log-summary.sh [logfile]   (defaults to ../logs/sample.log)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="${1:-$ROOT/logs/sample.log}"
[ -f "$LOG" ] || { echo "log file not found: $LOG" >&2; exit 1; }

echo "==================================================="
echo " Log summary: $LOG"
echo " Generated:   $(date -u '+%F %T UTC')"
echo "==================================================="

total=$(wc -l < "$LOG" | tr -d ' ')
echo "Total entries: $total"
echo

echo "-- Entries by level --"
awk '{for(i=1;i<=NF;i++) if($i ~ /^(DEBUG|INFO|WARN|ERROR)$/){c[$i]++; break}} END{for(l in c) printf "%7d  %s\n", c[l], l}' "$LOG" | sort -rn
echo

errors=$(grep -c ' ERROR ' "$LOG" || true)
awk -v e="${errors:-0}" -v t="$total" 'BEGIN{ if(t>0) printf "Error rate: %d/%d = %.1f%%\n", e, t, (e/t)*100 }'
echo

echo "-- Time span --"
echo "First entry: $(awk 'NR==1{print $1}' "$LOG")"
echo "Last entry:  $(awk 'END{print $1}' "$LOG")"
echo

echo "-- Top 5 ERROR messages --"
grep ' ERROR ' "$LOG" | sed -E 's/^[^ ]+ ERROR +//' | sort | uniq -c | sort -rn | head -5
echo

echo "-- HTTP status distribution --"
if grep -qoE 'status=[0-9]{3}' "$LOG"; then
    grep -oE 'status=[0-9]{3}' "$LOG" | sort | uniq -c | sort -rn
    echo "5xx server errors: $(grep -oE 'status=5[0-9]{2}' "$LOG" | wc -l | tr -d ' ')"
else
    echo "(no HTTP status fields found)"
fi
