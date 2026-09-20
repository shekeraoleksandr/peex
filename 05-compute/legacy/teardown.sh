#!/usr/bin/env bash
# Terminate the instance and remove the security group, key pair and local key.
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_login
load_state

echo "### TEARDOWN @ $(date -u '+%F %T UTC')"
echo "Will terminate instance $INSTANCE_ID, delete SG $SG_ID and key pair $KEY_NAME."
read -r -p "Proceed? [y/N] " ans
[ "${ans:-N}" = "y" ] || [ "${ans:-N}" = "Y" ] || { echo "aborted"; exit 0; }

echo "== Terminate instance =="
aws ec2 terminate-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
    --query 'TerminatingInstances[0].{Id:InstanceId,State:CurrentState.Name}' --output table
aws ec2 wait instance-terminated --region "$REGION" --instance-ids "$INSTANCE_ID" && echo "instance terminated"

echo "== Delete security group =="
aws ec2 delete-security-group --region "$REGION" --group-id "$SG_ID" && echo "SG deleted" || echo "SG delete skipped"

echo "== Delete key pair (AWS) and local private key =="
aws ec2 delete-key-pair --region "$REGION" --key-name "$KEY_NAME" && echo "key pair deleted in AWS"
rm -f "$KEY_FILE" "${KEY_FILE}.pub" && echo "local key removed"

rm -f "$STATE"
echo "TEARDOWN DONE"
