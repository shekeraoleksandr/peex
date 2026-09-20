#!/usr/bin/env bash
# sysreport v1 — the ORIGINAL, kept verbatim for comparison.
#
# What is wrong with it, and what v2/v3 fixed (see MODIFICATION.md):
#   * no arguments at all — output format and destination are hardcoded
#   * human-readable only; nothing downstream can consume it
#   * no --help, no error handling, no exit-code contract
#   * Linux-only: free/uptime -p do not exist on macOS, and it does not notice
set -euo pipefail
echo "Host   : $(hostname)"
echo "Kernel : $(uname -sr)"
echo "Uptime : $(uptime -p)"
echo "Memory : $(free -m | awk '/Mem:/{print $3"/"$2" MB"}')"
echo "Disk   : $(df -h / | awk 'NR==2{print $5}')"
