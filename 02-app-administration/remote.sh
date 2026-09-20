#!/usr/bin/env bash
# Deploy the PeEx web service to a REAL remote VM over SSH and collect proof.
# Run this FROM your machine (where SSH to the VM already works).
#
#   VM=ubuntu@<host> [SSH_KEY=~/.ssh/key] ./remote.sh <command>
#
# TIP: load your key into the agent once to avoid repeated passphrase prompts:
#   eval "$(ssh-agent -s)" && ssh-add --apple-use-keychain ~/.ssh/id_ed25519   # macOS
#   (Linux: ssh-add ~/.ssh/id_ed25519)
#
# Commands:
#   deploy | proof | maintenance | reboot-proof | all | teardown | ssh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
: "${VM:?set VM=user@host, e.g. VM=ubuntu@203.0.113.10}"
REMOTE_DIR="${REMOTE_DIR:-peex-app-admin}"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
[ -n "${SSH_KEY:-}" ] && SSH_OPTS+=(-i "$SSH_KEY")

rsh()   { ssh "${SSH_OPTS[@]}" "$VM" "$@"; }          # non-interactive
rsh_t() { ssh -t "${SSH_OPTS[@]}" "$VM" "$@"; }       # TTY, so remote sudo can prompt
rcp()   { scp "${SSH_OPTS[@]}" "$@"; }

# Pull the VM's proof/ back here reliably (tar over ssh — avoids scp
# path/glob quirks on macOS SFTP-mode scp).
pull_proof() {
    echo "==> Pulling proof/ back to $HERE/proof/"
    ssh "${SSH_OPTS[@]}" "$VM" "cd ~/$REMOTE_DIR && tar -czf - proof" | tar -xzf - -C "$HERE"
    echo "   -> $HERE/proof/"
    ls -1 "$HERE/proof/" | sed "s/^/     /"
}

do_deploy() {
    echo "==> Copying kit to $VM:~/$REMOTE_DIR"
    rsh "mkdir -p ~/$REMOTE_DIR"
    rcp -r "$HERE/config" "$HERE/maintenance" "$HERE"/*.sh "$VM:~/$REMOTE_DIR/"
    echo "==> Running install.sh on the VM (sudo — enter your VM password if asked)"
    rsh_t "cd ~/$REMOTE_DIR && chmod +x *.sh maintenance/*.sh && sudo ./install.sh"
}

do_proof() {
    echo "==> Collecting proof on the VM"
    rsh "cd ~/$REMOTE_DIR && ./collect-proof.sh"
    pull_proof
}

do_maintenance() {
    echo "==> Maintenance (healthcheck + upgrade + rollback) on the VM (sudo)"
    rsh_t "cd ~/$REMOTE_DIR && sudo ./maintenance/healthcheck.sh; sudo ./maintenance/upgrade.sh; sudo ./maintenance/rollback.sh"
    pull_proof || true
}

do_reboot_proof() {
    echo "==> Rebooting $VM to prove auto-start after OS restart"
    rsh "systemctl is-enabled peex-web" || true
    rsh_t "sudo reboot" || true
    sleep 15
    local ok=""
    for i in $(seq 1 24); do
        if rsh "true" 2>/dev/null; then ok=1; echo "  VM back online"; break; fi
        echo "  waiting for VM to come back ($i)..."; sleep 10
    done
    [ -n "$ok" ] || { echo "VM did not come back in time"; return 1; }
    echo "==> Service state after reboot:"
    rsh "systemctl is-active peex-web && cd ~/$REMOTE_DIR && REBOOT_PROOF=1 ./collect-proof.sh"
    pull_proof
}

case "${1:-all}" in
    deploy)        do_deploy ;;
    proof)         do_proof ;;
    maintenance)   do_maintenance ;;
    reboot-proof)  do_reboot_proof ;;
    all)           do_deploy; do_proof; do_reboot_proof ;;
    logs)          rsh_t "systemctl status peex-web.service --no-pager -l || true; echo ===== JOURNAL =====; sudo journalctl -xeu peex-web.service --no-pager | tail -60" ;;
    teardown)      rsh_t "cd ~/$REMOTE_DIR && sudo ./uninstall.sh" ;;
    ssh)           ssh "${SSH_OPTS[@]}" "$VM" ;;
    *) echo "usage: VM=user@host [SSH_KEY=path] $0 <deploy|proof|maintenance|reboot-proof|all|teardown|logs|ssh>"; exit 2 ;;
esac
