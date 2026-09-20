# Shared configuration for the PeEx Containers kit. Sourced by scripts/*.sh.
# No secrets here -- registry access comes from your logged-in gcloud CLI.
# shellcheck shell=bash
# shellcheck disable=SC2034  # consumed by the scripts that source this file
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Source repository (READ-ONLY -- nothing here ever writes to MovieLinks) --
: "${MOVIELINKS:=$ROOT/../../MovieLinks}"
LANDING="$MOVIELINKS/movieLinks-landing"

# --- Local image -------------------------------------------------------------
IMAGE_NAME="${IMAGE_NAME:-movielinks-landing}"
IMAGE_TAG="${IMAGE_TAG:-peex-local}"
LOCAL_IMAGE="$IMAGE_NAME:$IMAGE_TAG"
CONTAINER_NAME="${CONTAINER_NAME:-peex_movielinks_landing}"
HOST_PORT="${HOST_PORT:-8080}"
# The application's configuration file. It is the source of truth for the
# runtime port, so `update-config.sh` can change PORT there and every script
# follows automatically -- which is what makes the change a configuration
# change rather than an edit scattered across scripts.
ENV_FILE="${ENV_FILE:-$ROOT/config/app.env}"

_cfg_port="$(grep -E '^PORT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')"
CONTAINER_PORT="${CONTAINER_PORT:-${_cfg_port:-4000}}"   # ENV PORT / EXPOSE 4000 in the Dockerfile

# --- Artifact Registry (real coordinates, taken from the project's own
#     terraform.tfvars and the cloud-run-seo-deploy workflow) ------------------
GCP_PROJECT="${GCP_PROJECT:-movielinks-475222}"
GCP_REGION="${GCP_REGION:-europe-west1}"
GAR_HOST="$GCP_REGION-docker.pkg.dev"
GAR_LANDING_REPO="${GAR_LANDING_REPO:-movie-links-lending}"
GAR_LANDING_IMAGE="${GAR_LANDING_IMAGE:-lending-prod}"
GAR_FUNCTIONS_REPO="${GAR_FUNCTIONS_REPO:-movielinks-functions}"
GAR_LANDING_URI="$GAR_HOST/$GCP_PROJECT/$GAR_LANDING_REPO/$GAR_LANDING_IMAGE"
GAR_FUNCTIONS_URI="$GAR_HOST/$GCP_PROJECT/$GAR_FUNCTIONS_REPO"

PROOF="$ROOT/proof"
mkdir -p "$PROOF"

# Echo the command before running it, so proof/ shows "$ <command>" then output
# (same convention as 01-databases).
note() { echo; echo "\$ $*"; }

require() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: '$1' is not installed or not on PATH." >&2
        exit 1
    }
}

# --- HTTP probe --------------------------------------------------------------
# `curl <url> | head -n` is a trap, and it bit us for real: head closes the pipe
# as soon as it has its lines, curl is killed by SIGPIPE and exits 23
# ("Failure writing output to destination"), and under `set -o pipefail` that
# non-zero status is read as "the request failed". That is a false negative on a
# request that actually succeeded -- and without a trailing `|| true` it aborts
# the whole script under `set -e`.
#
# So: capture the whole response first, page it afterwards from a here-string
# (no pipe, so nothing can receive SIGPIPE), and judge the result by the HTTP
# status line rather than by an exit status.
http_show() {                       # http_show <url> [lines]
    local url="$1" lines="${2:-25}" resp rc=0 code
    resp="$(curl -sS -i -m 10 "$url" 2>&1)" || rc=$?
    head -n "$lines" <<<"$resp"
    code="$(awk 'NR==1 && /^HTTP/{print $2; exit}' <<<"$resp")"
    if [ -n "$code" ]; then
        echo "  [HTTP $code -- ${#resp} bytes received]"
    else
        echo "  (no HTTP response -- curl exit $rc)"
    fi
}

http_title() {                      # http_title <url>
    local body
    body="$(curl -sS -m 10 "$1" 2>/dev/null)" || true
    grep -o -m1 '<title>[^<]*</title>' <<<"$body" || echo "(no <title> in the response)"
}

check_landing() {
    [ -d "$LANDING/.git" ] || {
        echo "ERROR: $LANDING is not a git repo." >&2
        echo "Set MOVIELINKS=/path/to/MovieLinks if it lives elsewhere." >&2
        exit 1
    }
}
