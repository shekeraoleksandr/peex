#!/usr/bin/env bash
# strongSwan IPsec endpoint (IKEv2, PSK, transport mode).
# Encrypts traffic between the two private hosts that ride the VPC peering
# link, so the payload is protected and not merely isolated.
#
# Templated by Terraform: local_ip, remote_ip, psk, side.
set -euo pipefail
exec > >(tee /var/log/peex-userdata.log) 2>&1

export DEBIAN_FRONTEND=noninteractive

# The private-subnet host has no egress until the NAT instance has finished
# its own boot and installed its forwarding rules. Racing that produces an
# apt failure that looks like a broken image rather than a timing problem.
wait_for_internet() {
    local i
    for i in $(seq 1 60); do
        if curl -fsS -m 5 https://checkip.amazonaws.com >/dev/null 2>&1; then
            echo "  egress available after $((i * 10))s"
            return 0
        fi
        echo "  waiting for egress via NAT ($i/60)..."
        sleep 10
    done
    echo "ERROR: no egress after 10 minutes -- check the NAT instance and the private route table"
    return 1
}

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

wait_for_internet || true

wait_for_apt
apt-get update -y
wait_for_apt
# strongswan-starter is what provides the legacy `ipsec` CLI and the
# /etc/ipsec.conf stack used below; the metapackage alone is not enough on
# Ubuntu 24.04.
apt-get install -y strongswan strongswan-starter iputils-ping tcpdump curl

# node_exporter, so this host appears in Prometheus like the others.
NODE_EXPORTER_VERSION="1.8.2"
cd /tmp
if curl -fsSL -o node_exporter.tar.gz \
    "https://github.com/prometheus/node_exporter/releases/download/v$${NODE_EXPORTER_VERSION}/node_exporter-$${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"; then
    tar xzf node_exporter.tar.gz
    mv "node_exporter-$${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/node_exporter
    id -u node_exporter >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter
    cat > /etc/systemd/system/node_exporter.service <<'UNIT'
[Unit]
Description=Prometheus Node Exporter
After=network.target
[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable --now node_exporter
else
    echo "WARN: node_exporter download failed (non-fatal)"
fi

# ---------------------------------------------------------------- IPsec config
# Transport mode: the two hosts encrypt traffic between themselves. Tunnel mode
# would be the choice for routing whole subnets through a gateway pair; here
# the endpoints ARE the hosts, so transport mode is both simpler and correct.
cat > /etc/ipsec.conf <<CONF
config setup
    charondebug="ike 1, knl 1, cfg 0"

conn peex-private-link
    type=transport
    auto=start
    keyexchange=ikev2
    authby=secret
    left=${local_ip}
    right=${remote_ip}
    # AES-256 with SHA-256 integrity and a 2048-bit DH group.
    ike=aes256-sha256-modp2048!
    esp=aes256-sha256-modp2048!
    dpdaction=restart
    dpddelay=30s
    closeaction=restart
    keyingtries=%forever
CONF

# The PSK never reaches the repository; Terraform generates it at apply time.
cat > /etc/ipsec.secrets <<SECRET
${local_ip} ${remote_ip} : PSK "${psk}"
SECRET
chmod 600 /etc/ipsec.secrets

systemctl enable strongswan-starter
systemctl restart strongswan-starter

# Both sides boot at once, so the first attempt often loses the race with the
# peer still installing packages. Retry rather than leaving the tunnel down.
for attempt in 1 2 3 4 5 6; do
    sleep 20
    if ipsec status 2>/dev/null | grep -q "ESTABLISHED"; then
        echo "==> IPsec SA established on attempt $attempt"
        break
    fi
    echo "  IPsec not up yet (attempt $attempt/6), restarting connection..."
    ipsec restart >/dev/null 2>&1 || true
done

echo "==> IPsec status (side: ${side}):"
ipsec statusall || echo "WARN: 'ipsec statusall' failed -- is strongswan-starter running?"
systemctl is-active strongswan-starter || true

echo "ipsec user-data DONE (side ${side}, local ${local_ip}, remote ${remote_ip})"
