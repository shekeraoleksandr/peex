#!/usr/bin/env bash
# Local CI/CD pipeline runner — same stages as the CI configs, runnable without
# a CI service so the flow is reproducible and verifiable offline.
# Stages: lint -> test -> build -> deploy -> verify.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
BUILD="$ROOT/build"; rm -rf "$BUILD"; mkdir -p "$BUILD"
PORT="${APP_PORT:-8091}"
SERVER_PID=""
cleanup(){ [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true; }
trap cleanup EXIT

stage(){ echo; echo "==================== STAGE: $1 ===================="; }
die(){ echo "PIPELINE FAILED at stage: $1" | tee -a "$BUILD/pipeline-result.txt"; exit 1; }

VERSION="$(python3 -c "import json;print(json.load(open('config/app.config.json'))['version'])")"
echo "pipeline start $(date -u '+%F %T UTC')  app version=$VERSION" | tee "$BUILD/pipeline-result.txt"

stage "lint"
python3 -m py_compile app/*.py tests/*.py && echo "lint OK (py_compile)" || die lint

stage "test"
python3 -m unittest discover -s tests -v > "$BUILD/test-report.txt" 2>&1
tail -n 6 "$BUILD/test-report.txt"
grep -qE '\bOK\b' "$BUILD/test-report.txt" || die test
echo "tests OK"

stage "build"
ART="$BUILD/peex-cicd-demo-${VERSION}.tar.gz"
tar -czf "$ART" app config
echo "$ART" > "$BUILD/artifact.txt"
echo "built artifact: $(basename "$ART") ($(wc -c < "$ART") bytes)"

stage "deploy"
rm -rf "$BUILD/deploy"; mkdir -p "$BUILD/deploy"
tar -xzf "$ART" -C "$BUILD/deploy"
APP_CONFIG="$BUILD/deploy/config/app.config.json" APP_PORT="$PORT" \
    python3 "$BUILD/deploy/app/server.py" & SERVER_PID=$!
sleep 2
curl -fs "http://127.0.0.1:${PORT}/healthz" >/dev/null && echo "deploy OK (healthz 200)" || die deploy
echo "  / -> $(curl -fs http://127.0.0.1:${PORT}/)"
echo "  /version -> $(curl -fs http://127.0.0.1:${PORT}/version)"

stage "verify"
APP_PORT="$PORT" "$ROOT/pipeline/verify-results.sh" || die verify

echo | tee -a "$BUILD/pipeline-result.txt"
echo "PIPELINE SUCCEEDED (version $VERSION)" | tee -a "$BUILD/pipeline-result.txt"
