#!/usr/bin/env bash
# Why is the peer host silent? Deliberately blunt: no nested command
# substitutions (an empty one silently produces an empty --filters value and
# the command returns nothing, which is how the first version of this script
# managed to print blank sections), no error suppression, raw output.
set -uo pipefail          # NOT -e: every check must run even if one fails

# AWS CLI v2 pipes output through a pager when stdout is a TTY. Run this
# script from a terminal without this and every `--output json` section
# prints NOTHING -- which is exactly what happened on the first run here.
export AWS_PAGER=""
HERE="$(cd "$(dirname "$0")" && pwd)"
TFDIR="$HERE/../terraform"
cd "$TFDIR"

PEER_IP="$(terraform output -raw peer_host_ip)"
PEER_PUB="$(terraform output -raw peer_host_public_ip)"
WEB_IP="$(terraform output -raw web_public_ip)"

note() { echo; echo "=== $* ==="; }

echo "### PEER DIAGNOSIS @ $(date -u '+%F %T UTC')"
echo "peer private=$PEER_IP  public=$PEER_PUB"

MAIN_VPC="$(terraform output -raw vpc_id)"

note "1. What Terraform thinks exists"
terraform state list | grep -i peer

note "2. The instance, straight from AWS (state + why)"
PEER_ID="$(aws ec2 describe-instances \
    --filters "Name=private-ip-address,Values=$PEER_IP" \
    --query 'Reservations[].Instances[].InstanceId' --output text)"
echo "instance id: '${PEER_ID}'"

if [ -z "$PEER_ID" ] || [ "$PEER_ID" = "None" ]; then
    echo "!! No instance holds $PEER_IP. Listing every instance in the account:"
    aws ec2 describe-instances \
        --query 'Reservations[].Instances[].[InstanceId,State.Name,PrivateIpAddress,Tags[?Key==`Name`]|[0].Value]' \
        --output text
else
    aws ec2 describe-instances --instance-ids "$PEER_ID" \
        --query 'Reservations[].Instances[].{State:State.Name,Reason:StateReason.Message,Subnet:SubnetId,VPC:VpcId,PublicIP:PublicIpAddress,PrivateIP:PrivateIpAddress,SGs:SecurityGroups[].GroupId,SrcDstCheck:SourceDestCheck,Launched:LaunchTime}' \
        --output json

    note "3. Status checks (empty output here means the instance is NOT running)"
    aws ec2 describe-instance-status --instance-ids "$PEER_ID" --include-all-instances \
        --query 'InstanceStatuses[].{Instance:InstanceState.Name,InstanceCheck:InstanceStatus.Status,SystemCheck:SystemStatus.Status}' \
        --output json

    note "4. Console output -- boot messages even when SSH is dead"
    aws ec2 get-console-output --instance-id "$PEER_ID" --output text | tail -40
fi

note "5. Every route table in the peer VPC (is the return route really there?)"
aws ec2 describe-route-tables \
    --filters "Name=tag:Project,Values=PeEx" \
    --query 'RouteTables[].{RT:RouteTableId,Name:Tags[?Key==`Name`]|[0].Value,Subnets:Associations[].SubnetId,Routes:Routes[].[DestinationCidrBlock,VpcPeeringConnectionId,GatewayId,NetworkInterfaceId]}' \
    --output json

note "5b. MAIN VPC route tables -- do they carry the route to 10.43.0.0/16?"
aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$MAIN_VPC" \
    --query 'RouteTables[].{Name:Tags[?Key==`Name`]|[0].Value,Subnets:Associations[].SubnetId,Routes:Routes[].[DestinationCidrBlock,VpcPeeringConnectionId,GatewayId,NetworkInterfaceId,State]}' \
    --output json

note "5c. The peering connection itself"
aws ec2 describe-vpc-peering-connections \
    --query 'VpcPeeringConnections[].{Id:VpcPeeringConnectionId,Status:Status.Code,Requester:RequesterVpcInfo.CidrBlock,Accepter:AccepterVpcInfo.CidrBlock,Options:AccepterVpcInfo.PeeringOptions}' \
    --output json

note "6. Peer security group rules"
aws ec2 describe-security-groups --filters "Name=group-name,Values=*peer-sg" \
    --query 'SecurityGroups[].{Id:GroupId,Ingress:IpPermissions[].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp]}' \
    --output json

note "7. Can the web instance reach it? (same VPC as the private host)"
ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=15 -i "$(terraform output -raw ssh_key_path)" "ubuntu@$WEB_IP" \
    "ping -c 2 -W 3 $PEER_IP; echo '--- tcp/22 ---'; timeout 6 bash -c '</dev/tcp/$PEER_IP/22' && echo open || echo unreachable" 2>&1 \
    | grep -v "Warning: Permanently added"

echo
echo "DIAGNOSIS COMPLETE"
