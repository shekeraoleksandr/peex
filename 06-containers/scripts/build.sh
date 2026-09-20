#!/usr/bin/env bash
# Build the MovieLinks landing image locally from its own Dockerfile.
#
# WHY `git archive` INSTEAD OF `docker build .`:
# movieLinks-landing has no .dockerignore and its working tree is ~947MB
# (node_modules 606M, dist 128M, .git 92M). A plain `docker build .` would ship
# all of that as build context and `COPY . .` would bake it into the builder
# layer. `git archive HEAD` streams ONLY committed files (~116MB) as the build
# context, which:
#   * keeps the MovieLinks repo strictly read-only (nothing is written there),
#   * guarantees the image is built from committed source, not a dirty tree,
#   * ties the image to an exact commit (it is also tagged with the short SHA).
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
require docker
require git
check_landing

SHA="$(git -C "$LANDING" rev-parse --short HEAD)"
BRANCH="$(git -C "$LANDING" rev-parse --abbrev-ref HEAD)"

{
echo "### BUILD @ $(date -u '+%F %T UTC')"
echo "source repo: $LANDING"
echo "commit:      $SHA ($BRANCH)"
echo "image:       $LOCAL_IMAGE  (+ $IMAGE_NAME:$SHA)"

note "git -C \$LANDING log --oneline -3 -- Dockerfile"
git -C "$LANDING" log --oneline -3 -- Dockerfile

note "cat \$LANDING/Dockerfile"
cat "$LANDING/Dockerfile"

note "git -C \$LANDING archive --format=tar HEAD | wc -c   # build context size"
git -C "$LANDING" archive --format=tar HEAD | wc -c | awk '{printf "%d bytes (%.1f MB)\n", $1, $1/1024/1024}'
echo "(for contrast, the full working tree is ~947MB -- see README, .dockerignore finding)"

note "git -C \$LANDING archive --format=tar HEAD | docker build -t $LOCAL_IMAGE -t $IMAGE_NAME:$SHA -"
git -C "$LANDING" archive --format=tar HEAD | docker build -t "$LOCAL_IMAGE" -t "$IMAGE_NAME:$SHA" -

note "docker images $IMAGE_NAME"
docker images "$IMAGE_NAME"

echo
echo "BUILD DONE: $LOCAL_IMAGE"
} 2>&1 | tee "$PROOF/01_build.txt"
echo "==> Wrote $PROOF/01_build.txt"
