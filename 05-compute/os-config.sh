#!/usr/bin/env bash
# "Perform basic operating system configuration" (KEY)
#
# The outcome names it explicitly: create a user account or update a password,
# then VERIFY by confirming the account exists and that authentication with it
# works. Installing nginx via cloud-init is configuration, but it is not this.
#
# So: create a real login user with key-based auth and sudo, prove it did not
# exist beforehand, then authenticate AS that user in a fresh session.
set -euo pipefail
export AWS_PAGER=""
HERE="$(cd "$(dirname "$0")" && pwd)"
TFDIR="$HERE/../11-network/terraform"
PROOF="$HERE/proof"
mkdir -p "$PROOF"

NEW_USER="${NEW_USER:-peexops}"
USER_KEY="$HERE/.${NEW_USER}_key"      # git-ignored; belongs to this demo only

cd "$TFDIR"
WEB_IP="$(terraform output -raw web_public_ip)"
KEY="$(terraform output -raw ssh_key_path)"
case "$KEY" in /*) ;; *) KEY="$TFDIR/${KEY#./}" ;; esac
KNOWN_HOSTS="$HERE/.known_hosts_run"; rm -f "$KNOWN_HOSTS"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS"
          -o ConnectTimeout=15 -i "$KEY")

note() { echo; echo "\$ $*"; }

# A dedicated keypair for the new account: the point is to prove that THIS
# user authenticates, which reusing the existing admin key would not show.
if [ ! -f "$USER_KEY" ]; then
    ssh-keygen -t ed25519 -N "" -C "$NEW_USER@peex" -f "$USER_KEY" >/dev/null
fi
PUBKEY="$(cat "$USER_KEY.pub")"

{
echo "### BASIC OS CONFIGURATION — CREATE AND VERIFY A USER ACCOUNT"
echo "target : EC2 web instance $WEB_IP (Ubuntu 24.04)"
echo "user   : $NEW_USER"
echo "auth   : ed25519 key pair generated for this account specifically"

echo
echo "===== BEFORE: the account does not exist ====="
note "getent passwd $NEW_USER"
ssh "${SSH_OPTS[@]}" "ubuntu@$WEB_IP" "getent passwd $NEW_USER || echo '(no such user — as expected)'"

echo
echo "===== APPLYING THE CONFIGURATION ====="
note "useradd + sudo group + authorized_keys  (idempotent)"
ssh "${SSH_OPTS[@]}" "ubuntu@$WEB_IP" "
  set -e
  if id -u '$NEW_USER' >/dev/null 2>&1; then
      echo 'user already exists — re-running is safe'
  else
      sudo useradd --create-home --shell /bin/bash '$NEW_USER'
      echo 'user created'
  fi

  # sudo rights, granted through group membership rather than a bespoke
  # sudoers file, so the grant is visible in 'id' and easy to revoke.
  sudo usermod -aG sudo '$NEW_USER'

  # Key-based auth only. No password is set, so the account cannot be
  # brute-forced over SSH even if password auth were re-enabled later.
  sudo install -d -m 700 -o '$NEW_USER' -g '$NEW_USER' /home/$NEW_USER/.ssh
  echo '$PUBKEY' | sudo tee /home/$NEW_USER/.ssh/authorized_keys >/dev/null
  sudo chown $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh/authorized_keys
  sudo chmod 600 /home/$NEW_USER/.ssh/authorized_keys
  echo 'ssh key installed'
"

echo
echo "===== AFTER: the account exists, with the expected properties ====="
note "getent passwd $NEW_USER; id $NEW_USER"
ssh "${SSH_OPTS[@]}" "ubuntu@$WEB_IP" "getent passwd $NEW_USER; id $NEW_USER"

note "ls -la /home/$NEW_USER/.ssh   # permissions matter: sshd refuses loose modes"
ssh "${SSH_OPTS[@]}" "ubuntu@$WEB_IP" "sudo ls -la /home/$NEW_USER/.ssh"

echo
echo "===== VERIFICATION: authenticate AS the new user, in a new session ====="
echo "(this is the part the outcome actually asks for — existence alone is not proof)"
note "ssh -i .${NEW_USER}_key $NEW_USER@$WEB_IP 'whoami; id; hostname'"
if ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS" \
       -o ConnectTimeout=15 -o PasswordAuthentication=no -i "$USER_KEY" \
       "$NEW_USER@$WEB_IP" 'echo "authenticated as: $(whoami)"; id; hostname; echo "--- sudo works? ---"; sudo -n true && echo "sudo: OK (passwordless via group)" || echo "sudo: requires a password (expected — no password set)"'
then
    echo
    echo "  [OK] authentication as $NEW_USER succeeded"
else
    echo
    echo "  [FAILED] could not authenticate as $NEW_USER"
fi

echo
echo "===== The configuration is reflected in system behaviour ====="
note "last/lastlog entry for the new account"
ssh "${SSH_OPTS[@]}" "ubuntu@$WEB_IP" "sudo lastlog -u $NEW_USER 2>/dev/null || sudo last -n 3 $NEW_USER 2>/dev/null || echo '(no lastlog entry yet)'"

note "auth log shows the accepted key-based login"
ssh "${SSH_OPTS[@]}" "ubuntu@$WEB_IP" "sudo grep -i \"$NEW_USER\" /var/log/auth.log 2>/dev/null | tail -5 || echo '(auth.log not readable or empty)'"

echo
echo "OS CONFIGURATION DONE"
echo "Private key for $NEW_USER: 05-compute/.${NEW_USER}_key (git-ignored, demo only)"
} 2>&1 | tee "$PROOF/06_os_config_user.txt"

echo
echo "==> Wrote $PROOF/06_os_config_user.txt"
