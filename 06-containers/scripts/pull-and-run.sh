#!/usr/bin/env bash
# Pull an image FROM Artifact Registry and run it locally with port forwarding,
# proving the published image works the same as the locally built one.
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
require docker
require gcloud

REG_CONTAINER="${CONTAINER_NAME}_registry"
REG_PORT="${REG_PORT:-$((HOST_PORT + 1))}"

{
echo "### PULL FROM REGISTRY AND RUN @ $(date -u '+%F %T UTC')"
echo "registry image: $GAR_LANDING_URI"
echo "host port:      $REG_PORT -> $CONTAINER_PORT"

note "gcloud auth configure-docker $GAR_HOST --quiet"
gcloud auth configure-docker "$GAR_HOST" --quiet 2>&1 || true

# Resolve the most recently updated tag instead of assuming :latest exists.
note "# resolve the newest tag in the registry"
TAG="$(gcloud artifacts docker images list "$GAR_LANDING_URI" \
        --include-tags --format='value(tags)' --limit=1 --sort-by=~UPDATE_TIME 2>/dev/null \
        | tr ',' '\n' | head -1 || true)"
TAG="${TAG:-latest}"
REMOTE_IMAGE="$GAR_LANDING_URI:$TAG"
echo "using: $REMOTE_IMAGE"

note "docker pull $REMOTE_IMAGE"
docker pull "$REMOTE_IMAGE"

note "docker images --filter reference=$GAR_LANDING_URI"
docker images --filter "reference=$GAR_LANDING_URI" \
    --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}'

note "docker rm -f $REG_CONTAINER   # clean any previous run"
docker rm -f "$REG_CONTAINER" 2>/dev/null || echo "(nothing to remove)"

note "docker run -d --name $REG_CONTAINER -p $REG_PORT:$CONTAINER_PORT -e PORT=$CONTAINER_PORT $REMOTE_IMAGE"
docker run -d --name "$REG_CONTAINER" \
    -p "$REG_PORT:$CONTAINER_PORT" \
    -e PORT="$CONTAINER_PORT" \
    "$REMOTE_IMAGE"

echo
echo "-- waiting for the pulled image to serve --"
ok=""
for i in $(seq 1 30); do
    if curl -fsS -m 3 "http://localhost:$REG_PORT/" >/dev/null 2>&1; then
        ok=1; echo "   up after ${i}s"; break
    fi
    sleep 1
done

note "docker ps --filter name=$REG_CONTAINER"
docker ps --filter "name=$REG_CONTAINER" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

if [ -n "$ok" ]; then
    note "curl -i http://localhost:$REG_PORT/   # same functionality, from the registry image"
    http_show "http://localhost:$REG_PORT/" 25
else
    echo "WARN: no HTTP 200 within 30s -- logs below"
fi

note "docker logs --tail 20 $REG_CONTAINER"
docker logs --tail 20 "$REG_CONTAINER" 2>&1 || true

echo
echo "PULL AND RUN DONE"
echo "locally built image : http://localhost:$HOST_PORT/"
echo "registry image      : http://localhost:$REG_PORT/"
} 2>&1 | tee "$PROOF/05_pull_and_run.txt"
echo "==> Wrote $PROOF/05_pull_and_run.txt"
