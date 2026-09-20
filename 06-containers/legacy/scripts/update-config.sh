#!/usr/bin/env bash
# Update configuration for the containerized application (Trainee KEY):
# change env config and redeploy WITHOUT rebuilding the image.
# Usage: ./update-config.sh [ENV] [MESSAGE] [VERSION]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME=peex_app
IMAGE="${IMAGE:-peex-app:1.0.0}"
cd "$ROOT"

NEW_ENV="${1:-production}"
NEW_MSG="${2:-Hello from PeEx (updated)}"
NEW_VER="${3:-1.1.0}"

echo "== BEFORE (current config in container) =="
curl -s http://127.0.0.1:8080/ | grep -Eo '<h1[^>]*>.*</h1>|Environment:.*</p>|Version:.*</p>' || echo "(container not running yet)"

echo "== Update config/app.env =="
tmp="$(mktemp)"
sed -e "s/^APP_ENV=.*/APP_ENV=${NEW_ENV}/" \
    -e "s/^APP_MESSAGE=.*/APP_MESSAGE=${NEW_MSG}/" \
    -e "s/^APP_VERSION=.*/APP_VERSION=${NEW_VER}/" config/app.env > "$tmp" && mv "$tmp" config/app.env
grep -E '^APP_(ENV|MESSAGE|VERSION)=' config/app.env

echo "== Redeploy with new config (no rebuild) =="
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p 8080:8080 --env-file config/app.env "$IMAGE" >/dev/null
sleep 3

echo "== AFTER (new config in container) =="
curl -s http://127.0.0.1:8080/ | grep -Eo '<h1[^>]*>.*</h1>|Environment:.*</p>|Version:.*</p>'
