#!/usr/bin/env bash
# Build a basic container image (Trainee KEY).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${IMAGE:-peex-app:1.0.0}"
cd "$ROOT"
echo "== docker build -> $IMAGE =="
docker build -t "$IMAGE" .
echo
echo "== image details =="
docker image ls "$IMAGE"
docker image inspect "$IMAGE" --format 'Cmd={{.Config.Cmd}} User={{.Config.User}} Healthcheck={{if .Config.Healthcheck}}yes{{else}}no{{end}}'
