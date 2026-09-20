#!/usr/bin/env bash
# Smoke test: verifies the service serves expected content. Exit 0 = pass.
set -uo pipefail
PORT=8080
BASE="http://127.0.0.1:${PORT}"
fail=0
check() { # <desc> <condition-cmd...>
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then echo "PASS: $desc"; else echo "FAIL: $desc"; fail=1; fi
}

code_home="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/" || echo 000)"
check "homepage returns 200 (got $code_home)" test "$code_home" = "200"
check "homepage contains service marker" bash -c "curl -fsS '$BASE/' | grep -q 'PeEx demo web service'"
check "/healthz returns ok" bash -c "curl -fsS '$BASE/healthz' | grep -q ok"

if [ "$fail" -eq 0 ]; then echo "SMOKE TEST: PASS"; else echo "SMOKE TEST: FAIL"; fi
exit "$fail"
