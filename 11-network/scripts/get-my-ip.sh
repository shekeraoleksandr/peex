#!/usr/bin/env bash
# Prints your current public IP in /32 CIDR form, for TF_VAR_allowed_cidr.
set -euo pipefail
ip="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')"
echo "${ip}/32"
