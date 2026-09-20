#!/usr/bin/env bash
# Update configuration files (Trainee KEY): bump version / change environment /
# toggle a feature flag in config/app.config.json, then show before/after.
# Usage: ./update-config.sh [VERSION] [ENVIRONMENT]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="$ROOT/config/app.config.json"
NEW_VER="${1:-1.1.0}"
NEW_ENV="${2:-production}"

echo "== BEFORE =="; cat "$CFG"
python3 - "$CFG" "$NEW_VER" "$NEW_ENV" <<'PY'
import json, sys
path, ver, env = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = json.load(open(path))
cfg["version"] = ver
cfg["environment"] = env
cfg["greeting_enabled"] = not cfg.get("greeting_enabled", True)
json.dump(cfg, open(path, "w"), indent=2)
open(path, "a").write("\n")
PY
echo "== AFTER =="; cat "$CFG"
echo "Config updated. Re-run ./pipeline/run-local.sh to build & deploy the new version."
