#!/bin/bash
# Basic OS configuration applied automatically at first boot (cloud-init).
# Fully scripted — no manual steps. Proves "perform basic operating system configuration".
set -x
exec > /var/log/peex-osconfig.log 2>&1

# 1. Hostname
hostnamectl set-hostname peex-compute-demo

# 2. Timezone
timedatectl set-timezone Europe/Kyiv

# 3. Patch packages
dnf -y update

# 4. Install useful packages (monitoring + web service)
dnf -y install htop nginx

# 5. Dedicated non-login application user
id peexapp >/dev/null 2>&1 || useradd --system --shell /usr/sbin/nologin peexapp

# 6. Enable and start a service (starts on boot)
systemctl enable --now nginx

# 7. Marker so verification can confirm cloud-init finished
echo "peex-osconfig-complete $(date -u +%FT%TZ)" > /etc/peex-osconfig.done
