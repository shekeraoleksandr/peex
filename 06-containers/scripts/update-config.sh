#!/usr/bin/env bash
# "Update configuration for containerized application" (KEY)
#
# Modify a predefined value in an existing configuration FILE, apply it by
# recreating the container through the existing procedure (scripts/run.sh),
# and prove the new value reached the RUNNING application -- not just the file
# on disk. That last part is the one the outcome actually tests.
#
# The value changed here is PORT: the port the SSR server binds to inside the
# container. It is a good choice precisely because it is observable from three
# independent angles -- the file, the container's environment, and the socket
# the process is actually listening on.
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
require docker

NEW_PORT="${NEW_PORT:-4100}"
OLD_PORT="$(grep -E '^PORT=' "$ENV_FILE" | cut -d= -f2 | tr -d '[:space:]')"

inside_listening() {
    # What port is the app actually bound to, seen from inside the container?
    #
    # /proc/net/tcp lists the local address as HEX:HEX and column 4 is the
    # socket state -- 0A is LISTEN. The hex is converted on the HOST, not in
    # the container: `strtonum()` is a GNU awk extension and this image ships
    # busybox awk, so doing it inside silently printed nothing at all.
    local hex ports=""
    hex="$(docker exec "$CONTAINER_NAME" sh -c \
              'cat /proc/net/tcp /proc/net/tcp6 2>/dev/null' 2>/dev/null \
           | awk '$4 ~ /^0A$/ {split($2,a,":"); print a[2]}' | sort -u)" || true
    if [ -z "$hex" ]; then
        echo "  (no LISTEN socket found in /proc/net/tcp -- is the container running?)"
        return 0
    fi
    for h in $hex; do ports="$ports $((16#$h))"; done
    echo "  listening on:$ports"
}

{
echo "### UPDATE CONFIGURATION FOR A CONTAINERIZED APPLICATION"
echo "config file : config/app.env"
echo "change      : PORT $OLD_PORT -> $NEW_PORT"
echo "applied by  : recreating the container via scripts/run.sh (existing procedure)"

echo
echo "===== BEFORE ====="
note "cat config/app.env"
cat "$ENV_FILE"

note "docker inspect -f '{{json .Config.Env}}' $CONTAINER_NAME   # env of the RUNNING container"
docker inspect -f '{{json .Config.Env}}' "$CONTAINER_NAME" 2>/dev/null \
    | tr ',' '\n' | grep -Ei 'PORT|NODE_ENV' || echo "(container not running yet -- run scripts/run.sh first)"

note "docker ps   # published port mapping"
docker ps --filter "name=$CONTAINER_NAME" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

note "# ports the process is listening on INSIDE the container"
inside_listening

note "curl -s -o /dev/null -w '%{http_code}' http://localhost:$HOST_PORT/"
curl -s -o /dev/null -w '%{http_code}\n' -m 10 "http://localhost:$HOST_PORT/" || echo "000 (not serving)"

echo
echo "===== APPLYING THE CHANGE ====="
note "sed -i 's/^PORT=$OLD_PORT/PORT=$NEW_PORT/' config/app.env"
# Keep a copy so the change is revertible and the diff is showable.
cp "$ENV_FILE" "$ENV_FILE.before"
sed -i.tmp "s/^PORT=$OLD_PORT/PORT=$NEW_PORT/" "$ENV_FILE" && rm -f "$ENV_FILE.tmp"

note "diff config/app.env.before config/app.env"
diff "$ENV_FILE.before" "$ENV_FILE" || true

echo
note "./scripts/run.sh   # recreate the container using the existing procedure"
echo "(run.sh reads PORT from the same file, so the published mapping follows it)"
"$ROOT/scripts/run.sh" >/dev/null 2>&1 || echo "(run.sh reported a problem -- see its own proof file)"
sleep 3

echo
echo "===== AFTER ====="
note "cat config/app.env"
cat "$ENV_FILE"

note "docker inspect -f '{{json .Config.Env}}' $CONTAINER_NAME   # the change reached the container"
docker inspect -f '{{json .Config.Env}}' "$CONTAINER_NAME" 2>/dev/null \
    | tr ',' '\n' | grep -Ei 'PORT|NODE_ENV' || echo "(container not running)"

note "docker ps   # mapping now publishes the new internal port"
docker ps --filter "name=$CONTAINER_NAME" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

note "# the application is now LISTENING on $NEW_PORT inside the container"
echo "  (this is the proof that the config reached the running app, not just the file)"
inside_listening

note "curl -i http://localhost:$HOST_PORT/   # still served, through the new internal port"
http_show "http://localhost:$HOST_PORT/" 8

note "docker logs --tail 5 $CONTAINER_NAME   # container logs after the recreate"
docker logs --tail 5 "$CONTAINER_NAME" 2>&1 || true

echo
echo "CONFIG UPDATE APPLIED AND VERIFIED"
} 2>&1 | tee "$PROOF/06_update_config.txt"

echo
echo "==> Wrote $PROOF/06_update_config.txt"
echo
read -r -p "Revert config/app.env to PORT=$OLD_PORT and recreate? [Y/n] " ans
if [ "${ans:-Y}" != "n" ] && [ "${ans:-Y}" != "N" ]; then
    mv "$ENV_FILE.before" "$ENV_FILE"
    "$ROOT/scripts/run.sh" >/dev/null 2>&1 || true
    echo "==> Reverted to PORT=$OLD_PORT and recreated the container."
else
    rm -f "$ENV_FILE.before"
    echo "==> Left at PORT=$NEW_PORT."
fi
