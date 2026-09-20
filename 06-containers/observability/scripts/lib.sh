# Shared config for the container-observability kit. Sourced by scripts/*.sh.
# shellcheck shell=bash
# shellcheck disable=SC2034
set -euo pipefail

# AWS CLI v2 sends output to a pager when stdout is a TTY, which silently
# swallows every --output json result. Harmless when piped to tee, fatal
# when run interactively -- so pin it off everywhere.
export AWS_PAGER=""


HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"                 # .../06-containers/observability
NETWORK_TF="$ROOT/../../11-network/terraform"  # the stack that owns the EC2s
PROOF="$ROOT/proof"
REMOTE_DIR="${REMOTE_DIR:-peex-observability}"
mkdir -p "$PROOF"

note() { echo; echo "\$ $*"; }

require() {
    command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found on PATH." >&2; exit 1; }
}

# Pull connection details from the 11-network stack rather than hardcoding them.
load_targets() {
    require terraform
    [ -d "$NETWORK_TF" ] || { echo "ERROR: $NETWORK_TF not found." >&2; exit 1; }
    MON_IP="$(terraform -chdir="$NETWORK_TF" output -raw monitoring_public_ip)"
    WEB_PRIVATE_IP="$(terraform -chdir="$NETWORK_TF" output -raw web_private_ip)"
    KEY="$(terraform -chdir="$NETWORK_TF" output -raw ssh_key_path)"
    # terraform prints the key path relative to its own module directory
    case "$KEY" in
        /*) ;;
        *) KEY="$NETWORK_TF/${KEY#./}" ;;
    esac
    # A per-run known_hosts file. `terraform apply` replaces instances whenever
    # user_data changes, and a replaced instance comes back with a NEW host key
    # on the SAME elastic IP -- which makes ssh refuse to connect at all
    # ("REMOTE HOST IDENTIFICATION HAS CHANGED"). Scoping known_hosts to this
    # run sidesteps that without resorting to StrictHostKeyChecking=no, which
    # would silently accept a genuinely different host.
    KNOWN_HOSTS="$ROOT/.known_hosts_run"; rm -f "$KNOWN_HOSTS"
    SSH_OPTS=(-o StrictHostKeyChecking=accept-new
              -o UserKnownHostsFile="$KNOWN_HOSTS"
              -o ConnectTimeout=15 -i "$KEY")
}

rsh() { ssh "${SSH_OPTS[@]}" "ubuntu@$MON_IP" "$@"; }

# Run an instant PromQL query on the monitoring instance and print one line per
# series.
#
# The point of this helper is the EMPTY case. The previous version piped curl
# into a python one-liner with `2>/dev/null || true`: when Prometheus was down,
# the query was malformed, or the metric simply was not being collected, the
# section printed absolutely nothing -- and an empty section in a proof file is
# indistinguishable from a check that silently broke. Every failure mode now
# says which one it was.
promq() {                     # promq <query> [scale] [unit]
    local query="$1" scale="${2:-1}" unit="${3:-}" raw=""
    # Echo the query itself: the proof file doubles as the "example queries for
    # metrics and logs" artifact, so the PromQL has to be visible in it.
    echo "  PromQL: $query"
    raw="$(rsh "curl -sG -m 15 localhost:9090/api/v1/query --data-urlencode 'query=$query'" 2>/dev/null)" || raw=""
    SCALE="$scale" UNIT="$unit" python3 -c '
import json, os, sys
raw = sys.stdin.read().strip()
if not raw:
    print("  (no response from Prometheus -- is the stack up?)"); raise SystemExit
try:
    d = json.loads(raw)
except Exception:
    print("  (unparseable response: %s)" % raw[:140]); raise SystemExit
if d.get("status") != "success":
    print("  (query rejected by Prometheus: %s)" % d.get("error", "?")); raise SystemExit
res = d.get("data", {}).get("result", [])
if not res:
    print("  (query ran, but no series matched -- this metric is not being collected)")
    raise SystemExit
sc = float(os.environ["SCALE"]); un = os.environ["UNIT"]
for r in res:
    m = r.get("metric", {})
    name = m.get("name") or m.get("instance") or m.get("job") or "(unlabelled)"
    print("  %-30s %10.3f%s" % (name, float(r["value"][1]) * sc, un))
' <<<"$raw"
}
