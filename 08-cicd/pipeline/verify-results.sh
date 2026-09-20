#!/usr/bin/env bash
# Verify CI/CD pipeline execution results (Trainee KEY).
# Checks the artifacts/reports a pipeline run produced and (if a deployment is
# up) the running app. Exit 0 = all results verified.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
PORT="${APP_PORT:-8091}"
fail=0
ok(){ echo "  PASS: $1"; }
no(){ echo "  FAIL: $1"; fail=1; }

echo "== Verify pipeline execution results =="

# 1. tests passed
if grep -qE '\bOK\b' "$BUILD/test-report.txt" 2>/dev/null; then ok "unit tests reported OK"; else no "unit tests not OK (see build/test-report.txt)"; fi

# 2. build artifact exists
art="$(cat "$BUILD/artifact.txt" 2>/dev/null || true)"
if [ -n "$art" ] && [ -f "$art" ]; then ok "build artifact present: $(basename "$art")"; else no "build artifact missing"; fi

# 3. deployment healthy (if server is running)
if curl -fs "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    ver="$(curl -fs "http://127.0.0.1:${PORT}/version" 2>/dev/null)"
    ok "deployed app healthy; /version = $ver"
    cfgver="$(python3 -c "import json;print(json.load(open('$ROOT/config/app.config.json'))['version'])")"
    if echo "$ver" | grep -q "\"version\": \"$cfgver\""; then ok "deployed version matches config ($cfgver)"; else no "deployed version != config"; fi
else
    echo "  INFO: no running deployment on :$PORT (run ./pipeline/run-local.sh for the full flow)"
fi

echo
if [ "$fail" -eq 0 ]; then echo "VERIFY: all pipeline results OK"; else echo "VERIFY: FAILURES detected"; fi
exit "$fail"
