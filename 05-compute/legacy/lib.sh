# Shared config for the PeEx Compute kit. Sourced by the other scripts.
# No secrets here — credentials come from your logged-in aws CLI at runtime.
# shellcheck shell=bash
# shellcheck disable=SC2034  # consumed by scripts that source this file
set -euo pipefail
export AWS_PAGER=""

: "${REGION:=us-east-1}"
: "${INSTANCE_TYPE:=t3.micro}"          # predefined, free-tier-eligible type

PROJECT="peex-compute-demo"
KEY_NAME="peex-compute-key"
SG_NAME="peex-compute-sg"
HOSTNAME_TAG="peex-compute-demo"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY_FILE="$HERE/${KEY_NAME}.pem"        # PRIVATE key stays local (sensitive)
STATE="$HERE/state.env"
PROOF="$HERE/proof"
mkdir -p "$PROOF"

# Predefined image: latest Amazon Linux 2023 (x86_64) via the public SSM parameter
AL2023_SSM="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
SSH_USER="ec2-user"

require_login() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo "ERROR: aws CLI not logged in / cannot reach AWS. Run 'aws sts get-caller-identity'." >&2
        exit 1
    fi
}

load_state() {
    [ -f "$STATE" ] || { echo "ERROR: $STATE not found — run ./provision.sh first." >&2; exit 1; }
    # shellcheck disable=SC1090
    source "$STATE"
}

ssh_run() { # $1 = remote command(s)
    ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
        "${SSH_USER}@${PUBLIC_IP}" "$1"
}
