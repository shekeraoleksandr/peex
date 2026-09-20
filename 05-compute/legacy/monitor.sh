#!/usr/bin/env bash
# Monitor virtual machine resource usage (Trainee KEY):
#  - OS-level metrics over SSH (CPU, memory, disk, load)
#  - CloudWatch CPUUtilization for the instance
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_login
load_state

REMOTE='
echo "== uptime / load =="; uptime
echo "== CPU snapshot (top) =="; top -bn1 | head -12
echo "== memory =="; free -m
echo "== disk =="; df -h /
echo "== vmstat (3 samples) =="; vmstat 1 3
echo "== top processes by CPU =="; ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -6
'

{
echo "### MONITOR @ $(date -u '+%F %T UTC')  instance=$INSTANCE_ID ip=$PUBLIC_IP"
echo "===== OS-level resource usage (over SSH) ====="
ssh_run "$REMOTE"

echo
echo "===== CloudWatch CPUUtilization (last 30 min, 5-min avg) ====="
echo "(basic monitoring publishes every 5 min; may be empty right after launch)"
START="$(date -u -v-30M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '30 minutes ago' '+%Y-%m-%dT%H:%M:%SZ')"
END="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
aws cloudwatch get-metric-statistics --region "$REGION" \
    --namespace AWS/EC2 --metric-name CPUUtilization \
    --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
    --start-time "$START" --end-time "$END" --period 300 --statistics Average Maximum \
    --query 'sort_by(Datapoints,&Timestamp)[].{Time:Timestamp,AvgCPU:Average,MaxCPU:Maximum}' \
    --output table
echo
echo "MONITOR DONE"
} 2>&1 | tee "$PROOF/04_monitor.txt"
