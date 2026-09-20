# How to fill this folder

Run on the machine where `aws` is logged in (region us-east-1):

```bash
./provision.sh        # -> 01_provision.txt
sleep 90              # let cloud-init finish
./verify-access.sh    # -> 02_verify_access.txt
./os-config.sh        # -> 03_os_config.txt
./monitor.sh          # -> 04_monitor.txt
./teardown.sh         # clean up when done (no proof file)
```

Optional visuals for the reviewer: EC2 console screenshot of the running
instance (type + AMI + tags), and the Security Group inbound rule.

| Item | Proof |
|------|-------|
| Provision VM (predefined type + image) | 01_provision.txt |
| Verify VM access | 02_verify_access.txt |
| Basic OS configuration | 03_os_config.txt (+ cloud-init/user-data.sh) |
| Monitor VM resource usage | 04_monitor.txt |
