#!/usr/bin/env bash
# Run the whole container lifecycle and capture every artifact into proof/.
#   build -> run (port forwarding) -> inspect -> registry -> pull & run
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
SCRIPTS="$ROOT/scripts"

echo "=== 1/5 build ===";         "$SCRIPTS/build.sh"
echo "=== 2/5 run ===";           "$SCRIPTS/run.sh"
echo "=== 3/5 inspect ===";       "$SCRIPTS/inspect.sh"
echo "=== 4/5 registry ===";      "$SCRIPTS/registry.sh"      || echo "(registry step failed -- gcloud logged in?)"
echo "=== 5/5 pull and run ===";  "$SCRIPTS/pull-and-run.sh"  || echo "(pull step failed -- gcloud logged in?)"

echo
echo "==> proof/"
ls -1 "$PROOF" | sed 's/^/     /'
echo
echo "Containers still running (for browser screenshots):"
docker ps --filter "name=$CONTAINER_NAME" --format '  {{.Names}}  {{.Ports}}' || true
echo "Stop them with: docker rm -f ${CONTAINER_NAME} ${CONTAINER_NAME}_registry"
