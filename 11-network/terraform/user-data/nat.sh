#!/usr/bin/env bash
# Turn this instance into a NAT router for the private subnet.
set -euo pipefail
exec > >(tee /var/log/peex-userdata.log) 2>&1

# cloud-init has no terminal. iptables-persistent asks a debconf question
# ("save current rules?") during install, so without these two lines the
# install blocks forever and the private subnet silently never gets egress.
export DEBIAN_FRONTEND=noninteractive
echo 'iptables-persistent iptables-persistent/autosave_v4 boolean false' | debconf-set-selections
echo 'iptables-persistent iptables-persistent/autosave_v6 boolean false' | debconf-set-selections

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
apt-get install -y -o Dpkg::Options::=--force-confnew iptables-persistent netfilter-persistent

# 1) Forward packets between interfaces (off by default on Ubuntu).
cat > /etc/sysctl.d/99-peex-nat.conf <<'CONF'
net.ipv4.ip_forward = 1
net.ipv4.conf.all.send_redirects = 0
CONF
sysctl -p /etc/sysctl.d/99-peex-nat.conf

# 2) Rewrite the source address of forwarded traffic to this instance's own
#    address, so replies come back here and can be forwarded on. MASQUERADE
#    picks the interface address automatically, which survives an IP change.
PRIMARY_IF="$(ip -o -4 route show to default | awk '{print $5}' | head -1)"
echo "primary interface: $PRIMARY_IF"

# Idempotent: -C tests for the rule, -A only adds it when missing, so a
# re-run (or a reboot replaying user-data) cannot stack duplicates.
add_rule() { # $1 = table, rest = rule spec
    local table="$1"; shift
    if ! iptables -t "$table" -C "$@" 2>/dev/null; then
        iptables -t "$table" -A "$@"
    fi
}

add_rule nat POSTROUTING -o "$PRIMARY_IF" -s 10.42.0.0/16 -j MASQUERADE
add_rule filter FORWARD -i "$PRIMARY_IF" -o "$PRIMARY_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT
add_rule filter FORWARD -s 10.42.0.0/16 -j ACCEPT

# 3) Survive a reboot.
netfilter-persistent save

echo "==> NAT rules in place:"
iptables -t nat -L POSTROUTING -n -v
echo "==> FORWARD chain:"
iptables -L FORWARD -n -v | head -10
echo "==> ip_forward: $(cat /proc/sys/net/ipv4/ip_forward)"
echo "nat user-data DONE"
