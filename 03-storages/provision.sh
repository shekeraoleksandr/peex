#!/usr/bin/env bash
# Provision & configure a secure S3 bucket:
#  - public access blocked, encryption at rest (SSE-S3 + bucket key),
#    versioning, cost tags, and server access logging to a log bucket.
# Idempotent: safe to re-run.
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

{
echo "### PROVISION @ $(date -u '+%F %T UTC')"
echo "region=$REGION  account=$ACCOUNT_ID  bucket=$BUCKET"
echo

create_bucket() { # $1 = bucket name
    local b="$1"
    if aws s3api head-bucket --bucket "$b" 2>/dev/null; then
        echo "bucket $b already exists"
    elif [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$b" --region us-east-1
    else
        aws s3api create-bucket --bucket "$b" --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION"
    fi
}

harden_bucket() { # $1 = bucket name
    local b="$1"
    aws s3api put-public-access-block --bucket "$b" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    aws s3api put-bucket-encryption --bucket "$b" \
        --server-side-encryption-configuration \
        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
    aws s3api put-bucket-tagging --bucket "$b" \
        --tagging 'TagSet=[{Key=Project,Value=PeEx},{Key=Environment,Value=demo},{Key=Competency,Value=storages}]'
}

echo "== 1. Create primary bucket =="
create_bucket "$BUCKET"

echo "== 2. Block ALL public access =="
harden_bucket "$BUCKET"

echo "== 3. Enable versioning =="
aws s3api put-bucket-versioning --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled

echo "== 4. Server access logging =="
# Best-effort: log delivery setup can vary by account. Do not abort on failure.
set +e
create_bucket "$LOG_BUCKET"
harden_bucket "$LOG_BUCKET"
cat > /tmp/peex-logbucket-policy.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "S3ServerAccessLogsPolicy",
    "Effect": "Allow",
    "Principal": {"Service": "logging.s3.amazonaws.com"},
    "Action": "s3:PutObject",
    "Resource": "arn:aws:s3:::${LOG_BUCKET}/access-logs/*",
    "Condition": {
      "ArnLike": {"aws:SourceArn": "${BUCKET_ARN}"},
      "StringEquals": {"aws:SourceAccount": "${ACCOUNT_ID}"}
    }
  }]
}
JSON
aws s3api put-bucket-policy --bucket "$LOG_BUCKET" --policy file:///tmp/peex-logbucket-policy.json \
    && aws s3api put-bucket-logging --bucket "$BUCKET" --bucket-logging-status \
       "{\"LoggingEnabled\":{\"TargetBucket\":\"${LOG_BUCKET}\",\"TargetPrefix\":\"access-logs/\"}}" \
    && echo "access logging enabled -> s3://${LOG_BUCKET}/access-logs/" \
    || echo "WARN: access logging setup skipped (non-fatal)"
set -e

echo
echo "== 5. Verify configuration =="
echo "--- Public access block ---";  aws s3api get-public-access-block --bucket "$BUCKET"
echo "--- Encryption at rest ---";   aws s3api get-bucket-encryption   --bucket "$BUCKET"
echo "--- Versioning ---";           aws s3api get-bucket-versioning   --bucket "$BUCKET"
echo "--- Tags ---";                 aws s3api get-bucket-tagging      --bucket "$BUCKET"
echo "--- Logging ---";              aws s3api get-bucket-logging      --bucket "$BUCKET"
echo
echo "PROVISION DONE: s3://$BUCKET"
} 2>&1 | tee "$PROOF/01_provision.txt"
