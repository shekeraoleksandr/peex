#!/usr/bin/env bash
# "Monitor virtual machine resource usage" (KEY)
#
# The requirement is not a snapshot: it asks for data "for a defined time
# window" with "any visible changes or peaks" recorded, plus a written summary
# of what was collected, when, and how. So this samples CPU and memory on a
# schedule, deliberately induces a load spike mid-window so there is a real
# peak to observe, and writes the summary itself.
#
# No root-cause analysis, per the task description -- observe and record only.
set -euo pipefail
export AWS_PAGER=""
HERE="$(cd "$(dirname "$0")" && pwd)"
TFDIR="$HERE/../11-network/terraform"
PROOF="$HERE/proof"
mkdir -p "$PROOF"

SAMPLES="${SAMPLES:-36}"      # 36 samples
INTERVAL="${INTERVAL:-5}"     # every 5s  => a 3-minute window
SPIKE_AT="${SPIKE_AT:-15}"    # induce load at sample 15
SPIKE_FOR="${SPIKE_FOR:-40}"  # for 40 seconds

cd "$TFDIR"
WEB_IP="$(terraform output -raw web_public_ip)"
KEY="$(terraform output -raw ssh_key_path)"
case "$KEY" in /*) ;; *) KEY="$TFDIR/${KEY#./}" ;; esac
KNOWN_HOSTS="$HERE/.known_hosts_run"; rm -f "$KNOWN_HOSTS"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS"
          -o ConnectTimeout=15 -i "$KEY")

CSV="$PROOF/05_resource_samples.csv"
START_UTC="$(date -u '+%F %T UTC')"

echo "==> Sampling $SAMPLES times every ${INTERVAL}s (~$((SAMPLES * INTERVAL / 60)) min) on $WEB_IP"
echo "    A CPU load burst is induced at sample $SPIKE_AT for ${SPIKE_FOR}s, so the"
echo "    window contains a genuine peak rather than a flat idle line."

# Sampling runs entirely on the instance: one SSH session, no per-sample
# connection overhead skewing the very metrics being measured.
ssh "${SSH_OPTS[@]}" "ubuntu@$WEB_IP" "
  set -u
  # CPU busy % from /proc/stat deltas -- more precise than parsing top, and
  # it does not depend on top's column layout, which varies by version.
  read_cpu() { awk '/^cpu /{idle=\$5+\$6; total=0; for(i=2;i<=NF;i++) total+=\$i; print idle, total}' /proc/stat; }

  prev=(\$(read_cpu))
  echo 'sample,time_utc,cpu_busy_pct,mem_used_pct,load1,note'
  for i in \$(seq 1 $SAMPLES); do
    if [ \"\$i\" = \"$SPIKE_AT\" ]; then
      ( timeout $SPIKE_FOR sh -c 'while :; do :; done' >/dev/null 2>&1 & )
      ( timeout $SPIKE_FOR sh -c 'while :; do :; done' >/dev/null 2>&1 & )
      note='LOAD BURST STARTED'
    else
      note=''
    fi
    sleep $INTERVAL
    cur=(\$(read_cpu))
    didle=\$(( \${cur[0]} - \${prev[0]} )); dtotal=\$(( \${cur[1]} - \${prev[1]} ))
    if [ \"\$dtotal\" -gt 0 ]; then
      cpu=\$(awk -v i=\$didle -v t=\$dtotal 'BEGIN{printf \"%.1f\", 100*(1-i/t)}')
    else cpu=0; fi
    prev=(\"\${cur[@]}\")
    mem=\$(awk '/MemTotal/{t=\$2}/MemAvailable/{a=\$2}END{printf \"%.1f\", 100*(1-a/t)}' /proc/meminfo)
    l1=\$(cut -d' ' -f1 /proc/loadavg)
    echo \"\$i,\$(date -u +%H:%M:%S),\$cpu,\$mem,\$l1,\$note\"
  done
" | tee "$CSV"

END_UTC="$(date -u '+%F %T UTC')"

# ---- written summary, computed from the samples ---------------------------
{
echo "### VM RESOURCE USAGE — MONITORING WINDOW"
echo
echo "WHAT was collected : CPU busy %, memory used %, 1-minute load average"
echo "WHERE              : EC2 web instance $WEB_IP (t3.micro, Ubuntu 24.04)"
echo "HOW                : /proc/stat deltas and /proc/meminfo, sampled over SSH"
echo "                     (raw samples: proof/05_resource_samples.csv)"
echo "WHEN               : $START_UTC  ->  $END_UTC"
echo "WINDOW             : $SAMPLES samples at ${INTERVAL}s intervals"
echo
python3 - "$CSV" "$SPIKE_AT" <<'PY'
import csv, sys
rows = []
with open(sys.argv[1]) as fh:
    for r in csv.DictReader(fh):
        try:
            rows.append((int(r["sample"]), r["time_utc"], float(r["cpu_busy_pct"]),
                         float(r["mem_used_pct"]), float(r["load1"]), r.get("note","")))
        except (ValueError, KeyError):
            pass

if not rows:
    print("No samples parsed -- check the CSV."); raise SystemExit

spike_at = int(sys.argv[2])
cpu = [r[2] for r in rows]; mem = [r[3] for r in rows]; load = [r[4] for r in rows]
peak = max(rows, key=lambda r: r[2])
base = [r for r in rows if r[0] < spike_at]

def stat(name, vals, unit="%"):
    print(f"  {name:22s} min {min(vals):6.1f}{unit}   avg {sum(vals)/len(vals):6.1f}{unit}   max {max(vals):6.1f}{unit}")

print("OBSERVED VALUES")
stat("CPU busy", cpu); stat("Memory used", mem); stat("Load average (1m)", load, "")
print()
print("CHANGES AND PEAKS")
print(f"  Peak CPU {peak[2]:.1f}% at {peak[1]} UTC (sample {peak[0]}).")
if base:
    b = sum(r[2] for r in base)/len(base)
    print(f"  Pre-burst CPU averaged {b:.1f}%, so the peak is {peak[2]-b:+.1f} points above the")
    print(f"  idle baseline. The burst was induced on purpose at sample {spike_at}; it is")
    print(f"  not an unexplained event.")
mem_swing = max(mem) - min(mem)
print(f"  Memory moved {mem_swing:.1f} points across the window "
      f"({min(mem):.1f}% -> {max(mem):.1f}%)"
      + (" — essentially flat, as expected for an idle nginx host."
         if mem_swing < 5 else " — worth noting."))
print(f"  Load average peaked at {max(load):.2f} against 2 vCPUs.")
print()
print("NOTE: observation only. Per the task description, no root-cause analysis")
print("is performed here.")
PY
} 2>&1 | tee "$PROOF/05_resource_window.txt"

echo
echo "==> Wrote $PROOF/05_resource_window.txt"
echo "==> Raw samples: $CSV  (import into a spreadsheet for a graph artifact)"
