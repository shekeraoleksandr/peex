#!/usr/bin/env bash
# sysreport — a system report automation script.
#
# This is v3. See modify/MODIFICATION.md for the full v1 -> v2 -> v3 history
# and modify/sysreport.v1.sh for the original.
#
# v3 is the CROSS-PLATFORM round of maintenance. v2 was Linux-only in a way
# that did not announce itself: on macOS `free`, `nproc`, `/proc/loadavg` and
# `ps --sort` all fail, every one of those failures was swallowed by a
# `2>/dev/null` guard, and the report came out with three fields silently
# blank. A monitoring script that quietly reports nothing is worse than one
# that fails, because nothing downstream can tell the difference between
# "0 processes" and "I could not look".
#
# So every collector now has a per-OS implementation and an explicit
# "n/a (unsupported on <os>)" value when there is none.
#
# EXIT CODES (the contract for pipelines):
#   0  report produced
#   2  invalid usage (unknown flag, missing value)
#   3  the report could not be written to --out
set -euo pipefail
export LOG_TAG=sysreport
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/common.sh
source "$HERE/../lib/common.sh"

FORMAT=text
OUT=""
OS="${FORCE_OS:-$(uname -s)}"    # FORCE_OS lets the test suite drive both paths

usage() {
    cat <<EOF
Usage: sysreport.sh [--json] [--out FILE]

  --json      emit JSON instead of text (for pipelines and dashboards)
  --out FILE  write the report to FILE instead of stdout
  -h, --help  show this help

Examples:
  ./sysreport.sh                          # human-readable, to stdout
  ./sysreport.sh --json                   # machine-readable
  ./sysreport.sh --json --out /tmp/r.json # persist an artifact
  FORCE_OS=Linux ./sysreport.sh           # exercise the other platform path

Supported platforms: Linux and macOS (Darwin). On any other system the
platform-specific fields report "n/a (unsupported on <os>)" rather than
silently coming back empty.

Exit codes: 0 ok, 2 invalid usage, 3 could not write --out.
EOF
}

# --- argument parsing: validate everything BEFORE collecting anything -------
while [ $# -gt 0 ]; do
    case "$1" in
        --json) FORMAT=json ;;
        --out)
            [ $# -ge 2 ] || { warn "--out needs a path"; usage >&2; exit 2; }
            OUT="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) warn "unknown argument: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

if [ -n "$OUT" ]; then
    outdir="$(dirname "$OUT")"
    [ -d "$outdir" ] || { warn "output directory does not exist: $outdir"; exit 3; }
    [ -w "$outdir" ] || { warn "output directory is not writable: $outdir"; exit 3; }
fi

# --- platform layer ---------------------------------------------------------
na() { printf 'n/a (unsupported on %s)' "$OS"; }

collect_uptime() {
    case "$OS" in
      Linux)  uptime -p 2>/dev/null || uptime ;;
      Darwin)
        # macOS uptime has no -p, so derive it from the kernel's boot time.
        local boot now secs
        boot="$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/.*sec *= *\([0-9]*\).*/\1/p')"
        if [ -n "$boot" ]; then
            now="$(date +%s)"; secs=$((now - boot))
            printf 'up %dd %dh %dm' $((secs/86400)) $(((secs%86400)/3600)) $(((secs%3600)/60))
        else
            uptime
        fi ;;
      *) uptime 2>/dev/null || na ;;
    esac
}

collect_load() {
    case "$OS" in
      Linux)  cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || na ;;
      Darwin) sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1" "$2" "$3}' || na ;;
      *) na ;;
    esac
}

collect_cpus() {
    case "$OS" in
      Linux)  nproc 2>/dev/null || na ;;
      Darwin) sysctl -n hw.ncpu 2>/dev/null || na ;;
      *) na ;;
    esac
}

collect_memory() {
    case "$OS" in
      Linux)
        free -m 2>/dev/null | awk '/Mem:/{printf "%s/%s MB", $3, $2}' || na ;;
      Darwin)
        # macOS has no `free`. Total comes from sysctl; "used" is the sum of
        # the page classes that are genuinely occupied (active + wired +
        # compressed), which is the closest honest analogue to Linux's used.
        local total_mb pagesize used_pages
        total_mb="$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1024 / 1024 ))"
        pagesize="$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)"
        used_pages="$(vm_stat 2>/dev/null | awk -F: '
            /Pages active/      {gsub(/[ .]/,"",$2); a=$2}
            /Pages wired down/  {gsub(/[ .]/,"",$2); w=$2}
            /Pages occupied by compressor/ {gsub(/[ .]/,"",$2); c=$2}
            END {print a+w+c}')"
        if [ "$total_mb" -gt 0 ] && [ -n "$used_pages" ]; then
            printf '%s/%s MB' "$(( used_pages * pagesize / 1024 / 1024 ))" "$total_mb"
        else
            na
        fi ;;
      *) na ;;
    esac
}

collect_disk() {
    # df -h / is portable; column positions match on both platforms.
    df -h / 2>/dev/null | awk 'NR==2{print $3"/"$2" ("$5")"}' || na
}

collect_top_procs() {
    case "$OS" in
      Linux)  ps -eo comm,%cpu --sort=-%cpu 2>/dev/null | awk 'NR>1{print $1":"$2"%"}' | head -3 | paste -sd, - ;;
      Darwin) ps -Aco comm,%cpu -r 2>/dev/null       | awk 'NR>1{print $1":"$2"%"}' | head -3 | paste -sd, - ;;
      *) na ;;
    esac
}

host="$(hostname)"
kernel="$(uname -sr)"
up="$(collect_uptime)"
load="$(collect_load)"
cpus="$(collect_cpus)"
mem_used="$(collect_memory)"
disk_root="$(collect_disk)"
top_proc="$(collect_top_procs)"
[ -n "$top_proc" ] || top_proc="$(na)"

# JSON string escaping: a process name or hostname containing a quote or a
# backslash would otherwise produce a document no parser accepts.
jesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

emit() {
    if [ -n "$OUT" ]; then
        cat > "$OUT" || { warn "could not write $OUT"; exit 3; }
        log "report written to $OUT"
    else
        cat
    fi
}

if [ "$FORMAT" = json ]; then
    emit <<EOF
{
  "host": "$(jesc "$host")",
  "os": "$(jesc "$OS")",
  "kernel": "$(jesc "$kernel")",
  "uptime": "$(jesc "$up")",
  "loadavg": "$(jesc "$load")",
  "cpus": "$(jesc "$cpus")",
  "memory_used": "$(jesc "$mem_used")",
  "disk_root": "$(jesc "$disk_root")",
  "top_processes": "$(jesc "$top_proc")",
  "generated": "$(date -u '+%FT%TZ')"
}
EOF
else
    emit <<EOF
=== System report ($(date -u '+%F %T UTC')) ===
Host        : $host
Platform    : $OS
Kernel      : $kernel
Uptime      : $up
Load avg    : $load
CPUs        : $cpus
Memory used : $mem_used
Disk (/)    : $disk_root
Top procs   : $top_proc
EOF
fi
