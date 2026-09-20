#!/usr/bin/env bash
# Prove the access-control model:
#   - read-write role: upload AND download succeed
#   - read-only  role: download succeeds, upload is DENIED
#   - deterministic IAM policy simulation (works even if AssumeRole is restricted)
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TESTFILE="/tmp/peex-test-$$.txt"
echo "peex storages access test $(date -u '+%F %T UTC')" > "$TESTFILE"

assume() { # $1 = role arn ; exports temp creds into current shell
    local out
    if ! out="$(aws sts assume-role --role-arn "$1" --role-session-name peex \
                 --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
                 --output text 2>/tmp/peex-assume-err)"; then
        echo "ASSUME-ROLE FAILED for $1:"; cat /tmp/peex-assume-err
        return 1
    fi
    AWS_ACCESS_KEY_ID="$(echo "$out" | awk '{print $1}')"
    AWS_SECRET_ACCESS_KEY="$(echo "$out" | awk '{print $2}')"
    AWS_SESSION_TOKEN="$(echo "$out" | awk '{print $3}')"
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

{
echo "### ACCESS TESTS @ $(date -u '+%F %T UTC')  bucket=$BUCKET"
echo "(IAM is eventually consistent — allowing a few seconds for role propagation)"
sleep 8

echo
echo "===== READ-WRITE role: expect upload + download OK ====="
( set +e
  assume "$RW_ROLE_ARN" || exit 0
  echo "whoami:"; aws sts get-caller-identity --query Arn --output text
  echo "\$ upload (v1)"; aws s3 cp "$TESTFILE" "s3://$BUCKET/test.txt"; echo "upload rc=$?"
  echo "\$ download"; aws s3 cp "s3://$BUCKET/test.txt" "/tmp/peex-dl-rw.txt"; echo "download rc=$?"
  # Overwrite the SAME key so the bucket actually has something to version.
  # Uploading once only ever yields a single version, which proves versioning
  # is switched on but not that it retains prior copies.
  echo "second version $(date -u '+%F %T UTC')" >> "$TESTFILE"
  echo "\$ upload (v2, same key -> previous version must be retained)"
  aws s3 cp "$TESTFILE" "s3://$BUCKET/test.txt"; echo "upload rc=$?"
)

echo
echo "===== READ-ONLY role: expect download OK, upload DENIED ====="
( set +e
  assume "$RO_ROLE_ARN" || exit 0
  echo "whoami:"; aws sts get-caller-identity --query Arn --output text
  echo "\$ download (should succeed)"; aws s3 cp "s3://$BUCKET/test.txt" "/tmp/peex-dl-ro.txt"; echo "download rc=$?"
  echo "\$ upload (should be DENIED)"; aws s3 cp "$TESTFILE" "s3://$BUCKET/should-fail.txt"
  echo "upload rc=$?  (non-zero = correctly denied)"
  # "cannot upload or modify" also covers deletion -- the RO policy grants no
  # s3:DeleteObject, so prove that too rather than just asserting it.
  echo "\$ delete (should be DENIED)"; aws s3 rm "s3://$BUCKET/test.txt"
  echo "delete rc=$?  (non-zero = correctly denied)"
)

echo
echo "===== Deterministic IAM policy simulation ====="
( set +e
  echo "-- Read-only policy: GetObject should be allowed, PutObject denied --"
  # NOTE: pass the policy document as an inline string, not "file://...".
  # aws-cli's file:// URI resolution is unreliable for LIST-type parameters
  # like --policy-input-list (see aws/aws-cli#2124) and fails with
  # "Policy input list item 1 has invalid content" even for valid JSON.
  aws iam simulate-custom-policy \
      --policy-input-list "$(cat "$POLICIES/readonly-policy.json")" \
      --action-names s3:GetObject s3:PutObject \
      --resource-arns "$BUCKET_ARN/test.txt" \
      --query 'EvaluationResults[].[EvalActionName,EvalDecision]' --output text
  echo "-- Read-write policy: GetObject and PutObject should both be allowed --"
  aws iam simulate-custom-policy \
      --policy-input-list "$(cat "$POLICIES/readwrite-policy.json")" \
      --action-names s3:GetObject s3:PutObject \
      --resource-arns "$BUCKET_ARN/test.txt" \
      --query 'EvaluationResults[].[EvalActionName,EvalDecision]' --output text
)

echo
echo "===== Object versioning proof (multiple versions kept) ====="
aws s3api list-object-versions --bucket "$BUCKET" --prefix test.txt \
    --query 'Versions[].[Key,VersionId,IsLatest,LastModified,Size]' --output text 2>/dev/null || true
echo "-- version count (expect >= 2 after the two uploads above) --"
aws s3api list-object-versions --bucket "$BUCKET" --prefix test.txt \
    --query 'length(Versions)' --output text 2>/dev/null || true
echo "-- the PREVIOUS version is still retrievable by its VersionId --"
PREV_VID="$(aws s3api list-object-versions --bucket "$BUCKET" --prefix test.txt \
    --query 'Versions[?IsLatest==`false`] | [0].VersionId' --output text 2>/dev/null || true)"
if [ -n "${PREV_VID:-}" ] && [ "$PREV_VID" != "None" ]; then
    aws s3api get-object --bucket "$BUCKET" --key test.txt --version-id "$PREV_VID" \
        /tmp/peex-prev-version.txt >/dev/null 2>&1 \
        && echo "restored old version $PREV_VID:" && cat /tmp/peex-prev-version.txt
else
    echo "(no previous version yet -- re-run after the bucket has been written twice)"
fi

echo
echo "ACCESS TESTS DONE"
rm -f "$TESTFILE"
} 2>&1 | tee "$PROOF/03_access_tests.txt"
