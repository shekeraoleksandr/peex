# Shared configuration for the PeEx Storages kit. Sourced by the other scripts.
# No secrets here — credentials come from your logged-in aws CLI at runtime.
# shellcheck shell=bash
# shellcheck disable=SC2034  # these vars are consumed by the scripts that source this file
set -euo pipefail
export AWS_PAGER=""

# Region can be overridden:  REGION=eu-central-1 ./provision.sh
: "${REGION:=us-east-1}"

PROJECT="peex-storages-demo"
BASE="peex-storage-demo"

# Verify we are logged in and derive a globally-unique bucket name from the account id
if ! ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"; then
    echo "ERROR: aws CLI is not logged in / cannot reach AWS. Run 'aws sts get-caller-identity' first." >&2
    exit 1
fi

BUCKET="${BASE}-${ACCOUNT_ID}"
LOG_BUCKET="${BUCKET}-logs"

RO_POLICY_NAME="peex-s3-readonly"
RW_POLICY_NAME="peex-s3-readwrite"
RO_ROLE_NAME="peex-s3-readonly-role"
RW_ROLE_NAME="peex-s3-readwrite-role"

BUCKET_ARN="arn:aws:s3:::${BUCKET}"
RO_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${RO_POLICY_NAME}"
RW_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${RW_POLICY_NAME}"
RO_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${RO_ROLE_NAME}"
RW_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${RW_ROLE_NAME}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROOF="$HERE/proof"
POLICIES="$HERE/policies"
mkdir -p "$PROOF" "$POLICIES"
