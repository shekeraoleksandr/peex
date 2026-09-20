#!/usr/bin/env bash
# Provision a VM with a predefined type and image (Junior KEY).
# Creates: SSH key pair (public key imported, private stays local),
# a least-privilege security group (SSH from your IP only), and one EC2
# instance with basic OS config applied at boot via user-data. Idempotent-ish.
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_login

{
echo "### PROVISION @ $(date -u '+%F %T UTC')  region=$REGION type=$INSTANCE_TYPE"

echo "== Resolve predefined image (Amazon Linux 2023) =="
AMI_ID="$(aws ec2 describe-images --region "$REGION" \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
    --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text 2>/dev/null)"
if [ -z "$AMI_ID" ] || [ "$AMI_ID" = "None" ]; then
    AMI_ID="$(aws ssm get-parameters --region "$REGION" --names "$AL2023_SSM" \
        --query 'Parameters[0].Value' --output text)"
fi
echo "AMI: $AMI_ID"

echo "== SSH key pair =="
if [ ! -f "$KEY_FILE" ]; then
    ssh-keygen -t ed25519 -N '' -f "$KEY_FILE" -C "$KEY_NAME" >/dev/null
    chmod 600 "$KEY_FILE"
fi
if ! aws ec2 describe-key-pairs --region "$REGION" --key-names "$KEY_NAME" >/dev/null 2>&1; then
    aws ec2 import-key-pair --region "$REGION" --key-name "$KEY_NAME" \
        --public-key-material "fileb://${KEY_FILE}.pub" >/dev/null
    echo "imported key pair $KEY_NAME"
else
    echo "key pair $KEY_NAME already present"
fi

echo "== Default VPC / security group (SSH from your IP only) =="
VPC_ID="$(aws ec2 describe-vpcs --region "$REGION" --filters Name=isDefault,Values=true \
        --query 'Vpcs[0].VpcId' --output text)"
[ "$VPC_ID" = "None" ] && { echo "ERROR: no default VPC in $REGION"; exit 1; }
MYIP="$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')"
echo "your public IP: $MYIP"
SG_ID="$(aws ec2 describe-security-groups --region "$REGION" \
        --filters Name=group-name,Values="$SG_NAME" Name=vpc-id,Values="$VPC_ID" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)"
if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
    SG_ID="$(aws ec2 create-security-group --region "$REGION" \
        --group-name "$SG_NAME" --description "PeEx compute demo SSH" \
        --vpc-id "$VPC_ID" --query 'GroupId' --output text)"
fi
# ensure ingress rule for current IP (ignore duplicate error)
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
    --protocol tcp --port 22 --cidr "${MYIP}/32" >/dev/null 2>&1 || true
echo "security group: $SG_ID (SSH 22 from ${MYIP}/32)"

echo "== Launch instance =="
INSTANCE_ID="$(aws ec2 run-instances --region "$REGION" \
    --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" --security-group-ids "$SG_ID" \
    --user-data "file://$(dirname "$0")/cloud-init/user-data.sh" \
    --metadata-options 'HttpTokens=required,HttpEndpoint=enabled' \
    --tag-specifications \
      "ResourceType=instance,Tags=[{Key=Name,Value=$HOSTNAME_TAG},{Key=Project,Value=PeEx},{Key=Competency,Value=compute}]" \
    --query 'Instances[0].InstanceId' --output text)"
echo "instance: $INSTANCE_ID"

echo "== Wait until running =="
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
PUBLIC_IP="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
echo "public IP: $PUBLIC_IP"

cat > "$STATE" <<EOF
INSTANCE_ID=$INSTANCE_ID
SG_ID=$SG_ID
PUBLIC_IP=$PUBLIC_IP
AMI_ID=$AMI_ID
EOF
echo "state saved to $STATE"

echo "== Instance summary (predefined type + image) =="
aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].{Id:InstanceId,Type:InstanceType,Image:ImageId,State:State.Name,AZ:Placement.AvailabilityZone,PublicIp:PublicIpAddress}' \
    --output table

echo "PROVISION DONE. Wait ~60-90s for cloud-init, then run ./verify-access.sh"
} 2>&1 | tee "$PROOF/01_provision.txt"
