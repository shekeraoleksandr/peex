#!/usr/bin/env bash
# Run the basic container image and verify it serves (Trainee KEY).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${IMAGE:-peex-app:1.0.0}"
NAME=peex_app
cd "$ROOT"

docker rm -f "$NAME" >/dev/null 2>&1 || true
echo "== docker run =="
docker run -d --name "$NAME" -p 8080:8080 --env-file config/app.env "$IMAGE"
echo "waiting for startup..."; sleep 3

echo "== container status =="
docker ps --filter "name=$NAME" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
echo "== HTTP checks =="
curl -s -o /dev/null -w "GET /        -> %{http_code}\n" http://127.0.0.1:8080/
curl -s -w "GET /healthz -> " http://127.0.0.1:8080/healthz
echo "== homepage (config-driven content) =="
curl -s http://127.0.0.1:8080/ | grep -Eo '<h1[^>]*>.*</h1>|Environment:.*</p>|Version:.*</p>'
