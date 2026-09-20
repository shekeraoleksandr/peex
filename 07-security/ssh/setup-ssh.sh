#!/usr/bin/env bash
# Configure and use secure shell access (Junior KEY):
#  - generate a key pair (client),
#  - install the hardening drop-in (server, needs root),
#  - validate and show the EFFECTIVE hardened sshd settings.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DROPIN="$HERE/99-peex-hardening.conf"
KEY="${KEY:-$HOME/.ssh/peex_ed25519}"

echo "== 1. Generate an ed25519 key pair (if absent) =="
if [ ! -f "$KEY" ]; then
    mkdir -p "$(dirname "$KEY")"; chmod 700 "$(dirname "$KEY")"
    ssh-keygen -t ed25519 -N '' -f "$KEY" -C "peex-secure-shell"
fi
echo "public key: ${KEY}.pub"
cat "${KEY}.pub"

echo
echo "== 2. Validate the hardening drop-in =="
# Build a throwaway merged config so we can validate without touching the system.
# The drop-in goes FIRST — sshd takes the first value for each keyword, which
# mirrors how /etc/ssh/sshd_config.d/*.conf is Included at the top on real hosts.
TMP="$(mktemp)"
cat "$DROPIN" > "$TMP"
if [ -f /etc/ssh/sshd_config ]; then
    grep -vE '^\s*Include\s' /etc/ssh/sshd_config >> "$TMP" 2>/dev/null || true
fi
mkdir -p /run/sshd 2>/dev/null || sudo mkdir -p /run/sshd 2>/dev/null || true
if command -v sshd >/dev/null 2>&1; then
    sshd -t -f "$TMP" && echo "sshd config test: OK"
    echo "-- effective hardened settings --"
    sshd -T -f "$TMP" 2>/dev/null | grep -Ei \
      'permitrootlogin|passwordauthentication|pubkeyauthentication|permitemptypasswords|maxauthtries|x11forwarding|allowtcpforwarding|clientaliveinterval'
else
    echo "sshd binary not present here; on the server run: sudo sshd -t && sudo sshd -T"
fi
rm -f "$TMP"

echo
echo "== 3. Install on a server (run AS ROOT on the target host) =="
cat <<EOF
  sudo install -m 0644 $DROPIN /etc/ssh/sshd_config.d/99-peex-hardening.conf
  # add your PUBLIC key to the target user:
  #   ssh-copy-id -i ${KEY}.pub <user>@<host>    (or paste into ~/.ssh/authorized_keys)
  sudo sshd -t && sudo systemctl reload ssh || sudo systemctl reload sshd
EOF

echo
echo "== 4. USE it (client) =="
echo "  add ssh_client_config.sample to ~/.ssh/config, then:  ssh peex-demo"
echo "  or directly:  ssh -i $KEY -o IdentitiesOnly=yes <user>@<host>"
