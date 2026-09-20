# How to fill this folder

Run on the target host (most steps need no cloud access):

```bash
sudo ./access-review/access-review.sh            | tee proof/01_access_review.txt
./firewall/verify-firewall.sh firewall/firewall-baseline.txt firewall/sample-rules.txt | tee proof/02_firewall_verify.txt
#   (on a real host: sudo ./firewall/verify-firewall.sh | tee proof/02_firewall_verify.txt)
./ssh/setup-ssh.sh                               | tee proof/03_ssh_hardening.txt
```

| Item | Proof |
|------|-------|
| Prepare user access data for least-privilege review | 01_access_review.txt |
| Verify firewall rules against baseline | 02_firewall_verify.txt |
| Configure & use secure shell access | 03_ssh_hardening.txt (+ ssh/ files) |

Optional visuals: screenshot of `sshd -T` output, or the firewall table.
