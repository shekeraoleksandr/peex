#!/usr/bin/env bash
# Regression test proving the bug and the fix.
# Setup: an OLD log (10 days) and a NEW log (now); cleanup DAYS=7 should
# delete ONLY the old one. Runs both the broken and the fixed script.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DAYS=7
pass=0; fail=0
check(){ if [ "$1" = "$2" ]; then echo "  PASS: $3"; pass=$((pass+1)); else echo "  FAIL: $3 (got '$1' want '$2')"; fail=$((fail+1)); fi; }

make_fixture(){ # $1 = dir
    local d="$1"; mkdir -p "$d"
    local old; old="$(date -v-10d +%Y%m%d%H%M 2>/dev/null || date -d '10 days ago' +%Y%m%d%H%M)"
    : > "$d/old.log"; touch -t "$old" "$d/old.log"
    : > "$d/new.log"
}

echo "== FIXED script (expected: old.log deleted, new.log kept) =="
d1="$(mktemp -d)"; make_fixture "$d1"
"$HERE/cleanup.sh" "$d1" "$DAYS" >/dev/null 2>&1 || true
check "$([ -e "$d1/old.log" ] && echo yes || echo no)" "no"  "old.log removed by fixed"
check "$([ -e "$d1/new.log" ] && echo yes || echo no)" "yes" "new.log kept by fixed"
rm -rf "$d1"

echo "== BROKEN script (demonstrates the bug: deletes NEW, keeps OLD) =="
d2="$(mktemp -d)"; make_fixture "$d2"
"$HERE/broken-cleanup.sh" "$d2" "$DAYS" >/dev/null 2>&1 || true
check "$([ -e "$d2/new.log" ] && echo yes || echo no)" "no"  "broken wrongly deletes new.log"
check "$([ -e "$d2/old.log" ] && echo yes || echo no)" "yes" "broken wrongly keeps old.log"
rm -rf "$d2"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "The fix is verified and the bug is reproduced." || echo "Unexpected outcome."
exit "$fail"
