#!/usr/bin/env bash
# Evidence for the non-functional requirements: non-root user, minimal base,
# efficient layers, and no build junk in the final image.
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
require docker

{
echo "### IMAGE INSPECTION (best practices) @ $(date -u '+%F %T UTC')"
echo "image=$LOCAL_IMAGE"

note "docker inspect -f '{{.Config.User}}' $LOCAL_IMAGE   # runs as non-root?"
docker inspect -f '{{.Config.User}}' "$LOCAL_IMAGE"

note "docker run --rm --entrypoint sh $LOCAL_IMAGE -c 'id'   # effective uid inside"
docker run --rm --entrypoint sh "$LOCAL_IMAGE" -c 'id'

note "docker inspect -f '{{json .Config.ExposedPorts}}' $LOCAL_IMAGE   # EXPOSE"
docker inspect -f '{{json .Config.ExposedPorts}}' "$LOCAL_IMAGE"

note "docker inspect -f '{{json .Config.Cmd}}' $LOCAL_IMAGE   # CMD"
docker inspect -f '{{json .Config.Cmd}}' "$LOCAL_IMAGE"

note "docker inspect -f '{{json .Config.Env}}' $LOCAL_IMAGE   # NODE_ENV/PORT"
docker inspect -f '{{json .Config.Env}}' "$LOCAL_IMAGE"

note "docker images $IMAGE_NAME --format '{{.Repository}}:{{.Tag}}  {{.Size}}'"
docker images "$IMAGE_NAME" --format '{{.Repository}}:{{.Tag}}  {{.Size}}'

note "docker history $LOCAL_IMAGE   # layer efficiency (multi-stage: only final stage layers)"
docker history "$LOCAL_IMAGE" --format 'table {{.Size}}\t{{.CreatedBy}}' | head -20

note "docker run --rm --entrypoint sh $LOCAL_IMAGE -c 'ls -a /usr/src/app'   # what actually shipped"
docker run --rm --entrypoint sh "$LOCAL_IMAGE" -c 'ls -a /usr/src/app'

note "# confirm build-time junk did NOT make it into the final image"
docker run --rm --entrypoint sh "$LOCAL_IMAGE" -c '
  for d in .git src public .angular; do
    if [ -e "/usr/src/app/$d" ]; then echo "  $d: PRESENT (would be a finding)"; else echo "  $d: absent (good)"; fi
  done
  if [ -d /usr/src/app/dist ]; then
    echo "  dist:         present (expected - the built app)"
  else
    echo "  dist:         MISSING"
  fi
  if [ -d /usr/src/app/node_modules ]; then
    echo "  node_modules: present (expected - prod deps only, after npm prune --omit=dev)"
  else
    echo "  node_modules: MISSING"
  fi
'

note "docker run --rm --entrypoint sh $LOCAL_IMAGE -c 'ls node_modules | wc -l'   # prod dep count"
docker run --rm --entrypoint sh "$LOCAL_IMAGE" -c 'ls /usr/src/app/node_modules | wc -l'

echo
echo "INSPECTION DONE"
} 2>&1 | tee "$PROOF/03_inspect.txt"
echo "==> Wrote $PROOF/03_inspect.txt"
