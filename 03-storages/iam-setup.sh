#!/usr/bin/env bash
# Create two least-privilege IAM policies + roles for the bucket:
#   read-only  (download/list only)   and   read-write (upload/download/list).
# Roles are assumed via STS (no long-lived access keys, no plaintext secrets).
# Idempotent: re-running updates the policy to a new default version.
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

# ---- render least-privilege policy documents scoped to THIS bucket ----
cat > "$POLICIES/readonly-policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": "${BUCKET_ARN}"
    },
    {
      "Sid": "ReadObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:GetObjectVersion"],
      "Resource": "${BUCKET_ARN}/*"
    }
  ]
}
JSON

cat > "$POLICIES/readwrite-policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": "${BUCKET_ARN}"
    },
    {
      "Sid": "ReadWriteObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "${BUCKET_ARN}/*"
    }
  ]
}
JSON

cat > "$POLICIES/trust-policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::${ACCOUNT_ID}:root"},
    "Action": "sts:AssumeRole"
  }]
}
JSON

upsert_policy() { # $1 name  $2 arn  $3 file
    local name="$1" arn="$2" file="$3"
    if aws iam get-policy --policy-arn "$arn" >/dev/null 2>&1; then
        echo "policy $name exists -> creating new default version"
        aws iam create-policy-version --policy-arn "$arn" \
            --policy-document "file://$file" --set-as-default >/dev/null
    else
        aws iam create-policy --policy-name "$name" \
            --policy-document "file://$file" \
            --description "PeEx storages demo ($name)" >/dev/null
    fi
}

upsert_role() { # $1 role  $2 policy-arn
    local role="$1" polarn="$2"
    if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
        echo "role $role exists -> updating trust policy"
        aws iam update-assume-role-policy --role-name "$role" \
            --policy-document "file://$POLICIES/trust-policy.json"
    else
        aws iam create-role --role-name "$role" \
            --assume-role-policy-document "file://$POLICIES/trust-policy.json" \
            --description "PeEx storages demo role" \
            --tags Key=Project,Value=PeEx Key=Competency,Value=storages >/dev/null
    fi
    aws iam attach-role-policy --role-name "$role" --policy-arn "$polarn"
}

{
echo "### IAM SETUP @ $(date -u '+%F %T UTC')  account=$ACCOUNT_ID"
echo
echo "== Create/Update policies =="
upsert_policy "$RO_POLICY_NAME" "$RO_POLICY_ARN" "$POLICIES/readonly-policy.json"
upsert_policy "$RW_POLICY_NAME" "$RW_POLICY_ARN" "$POLICIES/readwrite-policy.json"

echo "== Create/Update roles and attach policies =="
upsert_role "$RO_ROLE_NAME" "$RO_POLICY_ARN"
upsert_role "$RW_ROLE_NAME" "$RW_POLICY_ARN"

echo
echo "== Read-only policy document =="
cat "$POLICIES/readonly-policy.json"
echo "== Read-write policy document =="
cat "$POLICIES/readwrite-policy.json"
echo
echo "== Roles =="
aws iam get-role --role-name "$RO_ROLE_NAME" --query 'Role.[RoleName,Arn]' --output text
aws iam get-role --role-name "$RW_ROLE_NAME" --query 'Role.[RoleName,Arn]' --output text
echo "== Attached policies =="
echo "RO:"; aws iam list-attached-role-policies --role-name "$RO_ROLE_NAME" --output text
echo "RW:"; aws iam list-attached-role-policies --role-name "$RW_ROLE_NAME" --output text
echo
echo "IAM SETUP DONE"
} 2>&1 | tee "$PROOF/02_iam.txt"
