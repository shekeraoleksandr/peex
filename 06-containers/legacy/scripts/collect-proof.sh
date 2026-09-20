#!/usr/bin/env bash
# Run the full container lifecycle and capture evidence into ../proof/.
# (Publishing to ECR is optional and captured separately — see README.)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/proof"; mkdir -p "$OUT"
cd "$ROOT" || exit 1

{ echo "### BUILD $(date -u '+%F %T UTC')"; scripts/build.sh; }        2>&1 | tee "$OUT/01_build.txt"
{ echo "### RUN";                          scripts/run.sh;   }        2>&1 | tee "$OUT/02_run.txt"
{ echo "### OBSERVE";                       scripts/observe.sh; }      2>&1 | tee "$OUT/03_observe.txt"
{ echo "### UPDATE CONFIG";                 scripts/update-config.sh; } 2>&1 | tee "$OUT/04_update_config.txt"
echo
echo "Optional publish step (needs aws): scripts/publish-ecr.sh | tee proof/05_publish.txt"
echo "Cleanup: docker rm -f peex_app"
