#!/usr/bin/env bash
# (Bonus) Prepare AWS IAM access data for a least-privilege review.
# Uses your logged-in aws CLI. Read-only.
set -uo pipefail
export AWS_PAGER=""
aws sts get-caller-identity >/dev/null 2>&1 || { echo "aws not logged in"; exit 1; }

echo "== IAM users =="
aws iam list-users --query 'Users[].{User:UserName,Created:CreateDate}' --output table

echo "== Users with AdministratorAccess (flag for review) =="
for u in $(aws iam list-users --query 'Users[].UserName' --output text); do
    if aws iam list-attached-user-policies --user-name "$u" \
         --query 'AttachedPolicies[?PolicyName==`AdministratorAccess`]' --output text | grep -q Administrator; then
        echo "  >> FLAG: $u has AdministratorAccess"
    fi
done

echo "== Credential report (age of keys, MFA, last used) =="
aws iam generate-credential-report >/dev/null 2>&1 || true
sleep 2
aws iam get-credential-report --query Content --output text 2>/dev/null | base64 --decode \
    | cut -d, -f1,4,5,6,9,10,11 || echo "  (credential report not available)"
