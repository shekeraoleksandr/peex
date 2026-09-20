# Clean-VM reproducibility test

Goal: prove `install.sh` reproduces the whole setup on a **second, clean VM**
with no manual steps (an acceptance-criteria artifact).

## Steps (easiest: reuse remote.sh against a second host)
1. Provision a second fresh Ubuntu 24.04 VM (the "clean VM").
2. Point the orchestrator at it and run the same flow — no manual steps:
   ```bash
   export VM=ubuntu@<second-vm-host>   SSH_KEY=~/.ssh/<key>
   ./remote.sh deploy      # install.sh runs on the clean VM
   ./remote.sh proof       # -> proof/00_deploy_proof.txt (from the clean VM)
   ./remote.sh reboot-proof# -> proof/01_after_reboot.txt
   ```
3. Expect `install.sh` to end with:
   `SUCCESS: peex-web is active and healthy on port 8080`.

(Or SSH in and run `sudo ./install.sh` + `./collect-proof.sh` directly.)

## What "pass" looks like
- `install.sh` completes with no manual intervention.
- `systemctl is-enabled peex-web` → `enabled`.
- `systemctl is-active peex-web` → `active` (also after reboot).
- `ps -C nginx -o user` shows `peexweb` (never `root`).
- `curl http://127.0.0.1:8080/healthz` → `ok`.
- No errors in `journalctl -u peex-web` or `/var/log/peex-web/error.log`.
