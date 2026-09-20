#!/usr/bin/env bash
# Boot-time OS configuration for the web/app instance (Ubuntu 24.04).
set -euo pipefail
exec > >(tee /var/log/peex-userdata.log) 2>&1

# cloud-init races unattended-upgrades for the dpkg lock on fresh Ubuntu
# instances -- wait it out instead of dying on "Could not get lock".
wait_for_apt() {
    local i
    for i in $(seq 1 60); do
        if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 &&
           ! fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
            return 0
        fi
        echo "  waiting for apt/dpkg lock ($i)..."
        sleep 5
    done
    echo "WARN: apt lock still held after 5 min, continuing anyway"
}

wait_for_apt
apt-get update -y
wait_for_apt
apt-get install -y nginx curl

HOSTNAME_F="$(hostname -f 2>/dev/null || hostname)"
cat > /var/www/html/index.html <<HTML
<html><body>
<h1>PeEx demo — web instance</h1>
<p>host: ${HOSTNAME_F}</p>
<p>provisioned by Terraform, inside a private VPC subnet, behind a security-group firewall.</p>
</body></html>
HTML

systemctl enable nginx
systemctl restart nginx

# node_exporter -- the metrics source Prometheus (on the monitoring instance)
# scrapes over the private VPC IP. Only reachable from the monitoring
# instance's security group (enforced in security-groups.tf), never from the
# public internet.
NODE_EXPORTER_VERSION="1.8.2"
cd /tmp
curl -fsSL -o node_exporter.tar.gz \
  "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
tar xzf node_exporter.tar.gz
mv "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/node_exporter
id -u node_exporter >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter

cat > /etc/systemd/system/node_exporter.service <<'UNIT'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable node_exporter
systemctl restart node_exporter

echo "web user-data DONE"
