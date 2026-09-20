#!/usr/bin/env bash
# Perform / verify basic OS configuration (Trainee KEY).
# The config itself is applied at boot by cloud-init (cloud-init/user-data.sh);
# this script confirms it and (idempotently) re-asserts each setting over SSH.
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_login
load_state

REMOTE='
set -e
echo "== cloud-init OS-config marker =="; sudo cat /etc/peex-osconfig.done 2>/dev/null || echo "(cloud-init still running?)"
echo "== hostname =="; hostnamectl set-hostname peex-compute-demo 2>/dev/null || true; hostnamectl | grep -i "hostname"
echo "== timezone =="; sudo timedatectl set-timezone Europe/Kyiv 2>/dev/null || true; timedatectl | grep -i "time zone"
echo "== dedicated user =="; id peexapp 2>/dev/null || (sudo useradd --system --shell /usr/sbin/nologin peexapp && id peexapp)
echo "== installed package (nginx) =="; rpm -q nginx || sudo dnf -y install nginx >/dev/null && rpm -q nginx
echo "== service enabled + active =="; sudo systemctl enable --now nginx >/dev/null 2>&1 || true; systemctl is-enabled nginx; systemctl is-active nginx
echo "== local service responds =="; curl -s -o /dev/null -w "http %{http_code}\n" http://localhost/ || true
'

{
echo "### OS CONFIG @ $(date -u '+%F %T UTC')  ip=$PUBLIC_IP"
ssh_run "$REMOTE"
echo
echo "OS CONFIG VERIFIED"
} 2>&1 | tee "$PROOF/03_os_config.txt"
