# How to fill this folder

`proof/` is empty in the kit — the live evidence is captured on the **real VM**
(Ubuntu 24.04) and pulled back here. A genuine systemd + reboot environment is
required, which is exactly what the VM provides.

Easiest — from your machine:
```bash
export VM=oleksandrshekera@192.168.64.8   SSH_KEY=~/.ssh/<key>
./remote.sh deploy
./remote.sh proof          # -> proof/00_deploy_proof.txt
./remote.sh maintenance    # upgrade + rollback output
./remote.sh reboot-proof   # -> proof/01_after_reboot.txt
```

Add screenshots of `systemctl status peex-web` and a browser on
`http://<vm>:8080/` if the reviewer wants visuals.

Artifacts map 1:1 to the PeEx "Outcome Artifacts":

| Artifact | Where in proof |
|----------|----------------|
| Installation script reproduces setup on a clean VM | `install.sh` + 00_deploy_proof.txt |
| Dedicated service-user creation | 00_deploy_proof.txt (`getent passwd peexweb`, `id`) |
| Customized configuration file | 00_deploy_proof.txt (nginx-peex.conf) |
| `systemctl status` | 00_deploy_proof.txt |
| Service runs under the correct user | 00_deploy_proof.txt (`ps -C nginx -o user`) |
| Auto-start after OS reboot | 01_after_reboot.txt |
| Healthy logs | 00_deploy_proof.txt (journalctl / error.log) |
| Second clean VM | point `VM` at another host and re-run `deploy`+`proof` (see ../CLEAN-VM-TEST.md) |
