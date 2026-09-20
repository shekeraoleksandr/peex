#!/usr/bin/env bash
# Remove everything this kit created, so no resources linger and incur cost.
# Deletes: primary bucket (all versions), log bucket, IAM roles and policies.
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

empty_versioned_bucket() { # $1 = bucket
    local b="$1"
    aws s3api head-bucket --bucket "$b" 2>/dev/null || { echo "  ($b absent)"; return 0; }
    echo "  emptying $b (objects + versions + delete markers)"
    # delete current objects (unversioned convenience pass)
    aws s3 rm "s3://$b" --recursive >/dev/null 2>&1 || true

    # Delete all versions + delete markers in batches. NOTE: earlier this used
    # a single --query combining Versions[] and DeleteMarkers[] with "+", which
    # is not valid JMESPath (no array-concat operator) and made the AWS CLI
    # call fail every time; under `set -e` that silently killed the whole
    # script right after printing "emptying ..." with nothing actually
    # deleted. Fixed by querying each list separately and merging with python3.
    local i=0
    while :; do
        i=$((i + 1))
        [ "$i" -gt 50 ] && { echo "  WARN: stopped after 50 batches, check manually"; break; }
        local vjson djson n
        vjson="$(aws s3api list-object-versions --bucket "$b" --max-items 1000 \
                 --query 'Versions[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null)" || vjson='[]'
        djson="$(aws s3api list-object-versions --bucket "$b" --max-items 1000 \
                 --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null)" || djson='[]'
        [ -z "$vjson" ] && vjson='[]'
        [ -z "$djson" ] && djson='[]'
        n="$(python3 -c "
import json, sys
v = json.loads(sys.argv[1]) or []
d = json.loads(sys.argv[2]) or []
print(len(v) + len(d))
" "$vjson" "$djson" 2>/dev/null)" || n=0
        [ "${n:-0}" -eq 0 ] && break
        python3 -c "
import json, sys
v = json.loads(sys.argv[1]) or []
d = json.loads(sys.argv[2]) or []
print(json.dumps({'Objects': v + d}))
" "$vjson" "$djson" > /tmp/peex-del.json
        aws s3api delete-objects --bucket "$b" --delete "file:///tmp/peex-del.json" >/dev/null 2>&1 || { echo "  WARN: delete-objects batch failed, stopping"; break; }
    done
}

echo "### TEARDOWN @ $(date -u '+%F %T UTC')  account=$ACCOUNT_ID"
read -r -p "Delete bucket '$BUCKET', its log bucket and IAM roles/policies? [y/N] " ans
[ "${ans:-N}" = "y" ] || [ "${ans:-N}" = "Y" ] || { echo "aborted"; exit 0; }

echo "== Buckets =="
empty_versioned_bucket "$BUCKET"
if aws s3api delete-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo "  deleted $BUCKET"
else
    echo "  WARN: could not delete $BUCKET (already gone, or not yet empty)"
fi

empty_versioned_bucket "$LOG_BUCKET"
if aws s3api delete-bucket --bucket "$LOG_BUCKET" 2>/dev/null; then
    echo "  deleted $LOG_BUCKET"
else
    echo "  WARN: could not delete $LOG_BUCKET (already gone, or not yet empty)"
fi

echo "== Roles =="
for role in "$RO_ROLE_NAME" "$RW_ROLE_NAME"; do
    for arn in $(aws iam list-attached-role-policies --role-name "$role" \
                 --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
        aws iam detach-role-policy --role-name "$role" --policy-arn "$arn" 2>/dev/null || true
    done
    if aws iam delete-role --role-name "$role" 2>/dev/null; then
        echo "  deleted role $role"
    else
        echo "  WARN: could not delete role $role (already gone?)"
    fi
done

echo "== Policies =="
for arn in "$RO_POLICY_ARN" "$RW_POLICY_ARN"; do
    # delete non-default versions first
    for v in $(aws iam list-policy-versions --policy-arn "$arn" \
               --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null); do
        aws iam delete-policy-version --policy-arn "$arn" --version-id "$v" 2>/dev/null || true
    done
    if aws iam delete-policy --policy-arn "$arn" 2>/dev/null; then
        echo "  deleted policy $arn"
    else
        echo "  WARN: could not delete policy $arn (already gone?)"
    fi
done

echo "TEARDOWN DONE"
