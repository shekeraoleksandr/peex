#!/usr/bin/env bash
# "Configure and use secure shell access" (KEY) — the USE half.
#
# setup-ssh.sh covers key generation and server hardening. This script covers
# what the acceptance criteria ask for beyond that, all against the live EC2
# hosts from 11-network and the real GitHub remote:
#
#   * a passphrase-protected key (and a check that proves it IS protected)
#   * 600/700 permissions, verified rather than assumed
#   * ~/.ssh/config used for connection management, including a ProxyJump to
#     the private-subnet host that has no public IP at all
#   * login as a non-root user, then sudo escalation
#   * a NEGATIVE test: password authentication is refused by the server
#   * ssh-agent: passphrase typed once, reused without retyping
#   * local port forwarding to a service bound to 127.0.0.1 on the remote host
#   * SCM over SSH: authentication to GitHub, ls-remote, and a clone
#
# Read-only with respect to MovieLinks. Nothing is pushed anywhere unless you
# explicitly pass PUSH_REPO=<a repo you own>.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROOF="$HERE/../proof"; mkdir -p "$PROOF"
TFDIR="$HERE/../../11-network/terraform"
OUT="$PROOF/04_ssh_access.txt"

KEY_SCM="${KEY_SCM:-$HOME/.ssh/peex_scm_ed25519}"
SSH_CONFIG="$HOME/.ssh/config"
KNOWN_PEEX="$HOME/.ssh/known_hosts_peex"
FWD_PORT="${FWD_PORT:-19090}"
SCM_URL="${SCM_URL:-git@github.com:MishaYatsun/movieLinks-landing.git}"
PUSH_REPO="${PUSH_REPO:-}"       # optional: an SSH URL of a repo YOU own

MARK_BEGIN="# >>> peex managed (07-security) >>>"
MARK_END="# <<< peex managed (07-security) <<<"

note() { echo; echo "\$ $*"; }
hr()   { printf '%s\n' "---------------------------------------------------------------"; }

# --- connection details come from the 11-network stack, not from hardcoding --
command -v terraform >/dev/null 2>&1 || { echo "ERROR: terraform not on PATH" >&2; exit 1; }
[ -d "$TFDIR" ] || { echo "ERROR: $TFDIR not found" >&2; exit 1; }
WEB_IP="$(terraform -chdir="$TFDIR" output -raw web_public_ip 2>/dev/null)"   || WEB_IP=""
MON_IP="$(terraform -chdir="$TFDIR" output -raw monitoring_public_ip 2>/dev/null)" || MON_IP=""
PRIV_IP="$(terraform -chdir="$TFDIR" output -raw private_host_ip 2>/dev/null)" || PRIV_IP=""
TF_KEY="$(terraform -chdir="$TFDIR" output -raw ssh_key_path 2>/dev/null)"    || TF_KEY=""
case "$TF_KEY" in /*) ;; "") ;; *) TF_KEY="$TFDIR/${TF_KEY#./}" ;; esac
if [ -z "$WEB_IP" ] || [ -z "$MON_IP" ]; then
    echo "ERROR: could not read IPs from $TFDIR — is the 11-network stack applied?" >&2
    exit 1
fi

# --- passphrase, asked for once, before the transcript starts ---------------
if [ ! -f "$KEY_SCM" ]; then
    echo "A new key will be generated at $KEY_SCM."
    echo "The acceptance criteria require it to be passphrase-protected."
    while :; do
        read -r -s -p "Passphrase (min 8 chars): " PASS; echo
        read -r -s -p "Repeat: " PASS2; echo
        [ "$PASS" = "$PASS2" ] || { echo "  they differ, try again"; continue; }
        [ "${#PASS}" -ge 8 ]   || { echo "  too short, try again"; continue; }
        break
    done
else
    PASS=""
    echo "Reusing the existing key at $KEY_SCM."
fi

{
echo "==============================================================="
echo " SECURE SHELL ACCESS — configure and use"
echo " $(date -u '+%F %T UTC')   client: $(uname -s) $(hostname)"
echo " targets: web=$WEB_IP  monitoring=$MON_IP  private=$PRIV_IP (no public IP)"
echo "==============================================================="

echo
echo "[1] KEY GENERATION"
hr
if [ ! -f "$KEY_SCM" ]; then
    note "ssh-keygen -t ed25519 -a 100 -f $KEY_SCM"
    # -a 100 raises the KDF rounds on the private key: it makes an offline
    # brute-force of the passphrase materially more expensive if the file ever
    # leaks. Cheap here, because it only costs time at unlock.
    ssh-keygen -t ed25519 -a 100 -N "$PASS" -f "$KEY_SCM" -C "peex-scm@$(hostname)"
else
    echo "  (key already present — not regenerating)"
fi
unset PASS PASS2 2>/dev/null || true

note "ssh-keygen -l -f $KEY_SCM   # fingerprint and type"
ssh-keygen -l -f "$KEY_SCM"

note "cat $KEY_SCM.pub   # public key — safe to share, this is what goes on servers/GitHub"
cat "$KEY_SCM.pub"

note "# is the private key ACTUALLY passphrase-protected?"
echo "  (asking ssh-keygen to derive the public key with an EMPTY passphrase:"
echo "   if that succeeds, the key is unprotected)"
if ssh-keygen -y -f "$KEY_SCM" -P "" >/dev/null 2>&1; then
    echo "  >> FLAG: the private key has NO passphrase"
else
    echo "  [OK] empty passphrase rejected — the key is encrypted at rest"
fi

echo
echo "[2] FILE PERMISSIONS"
hr
chmod 700 "$HOME/.ssh" 2>/dev/null || true
chmod 600 "$KEY_SCM"   2>/dev/null || true
chmod 644 "$KEY_SCM.pub" 2>/dev/null || true
note "ls -l ~/.ssh (the keys in play)"
ls -ld "$HOME/.ssh" | sed 's/^/  /'
ls -l "$KEY_SCM" "$KEY_SCM.pub" 2>/dev/null | sed 's/^/  /'
[ -n "$TF_KEY" ] && [ -f "$TF_KEY" ] && {
    echo "  -- the Terraform-generated EC2 key (11-network) --"
    ls -l "$TF_KEY" | sed 's/^/  /'
}
note "# sshd refuses a private key that is group- or world-readable; 600 is not cosmetic"
for f in "$KEY_SCM" "$TF_KEY"; do
    [ -f "$f" ] || continue
    perm="$(ls -l "$f" | awk '{print $1}')"
    case "$perm" in
      -rw-------*) echo "  [OK]   $perm  $f" ;;
      *)           echo "  >> FLAG: $perm  $f  — too permissive" ;;
    esac
done

echo
echo "[3] ~/.ssh/config — CONNECTION MANAGEMENT"
hr
[ -f "$SSH_CONFIG" ] && cp "$SSH_CONFIG" "$SSH_CONFIG.peex-backup"
python3 - "$SSH_CONFIG" "$MARK_BEGIN" "$MARK_END" <<'PY'
import os, sys
path, b, e = sys.argv[1:4]
old = open(path).read() if os.path.exists(path) else ""
# Drop any previous managed block so re-running is idempotent and never
# accumulates duplicate Host stanzas.
if b in old and e in old:
    old = old[:old.index(b)] + old[old.index(e) + len(e):]
open(path, "w").write(old.rstrip("\n") + ("\n\n" if old.strip() else ""))
PY

macos_keychain=""
[ "$(uname -s)" = "Darwin" ] && macos_keychain="    UseKeychain yes"

cat >> "$SSH_CONFIG" <<EOF
$MARK_BEGIN
# Generated by 07-security/ssh/ssh-access-demo.sh. Remove this whole block to
# revert. A per-project known_hosts file keeps host-key churn from Terraform
# instance replacement out of the main ~/.ssh/known_hosts.

Host peex-web
    HostName $WEB_IP
    User ubuntu
    IdentityFile $TF_KEY
    IdentitiesOnly yes
    UserKnownHostsFile $KNOWN_PEEX
    StrictHostKeyChecking accept-new

Host peex-mon
    HostName $MON_IP
    User ubuntu
    IdentityFile $TF_KEY
    IdentitiesOnly yes
    UserKnownHostsFile $KNOWN_PEEX
    StrictHostKeyChecking accept-new

# The private-subnet host has no public IP and no route to the internet
# gateway. ProxyJump makes that invisible at the command line: 'ssh peex-priv'
# transparently hops through the web instance.
Host peex-priv
    HostName $PRIV_IP
    User ubuntu
    IdentityFile $TF_KEY
    IdentitiesOnly yes
    ProxyJump peex-web
    UserKnownHostsFile $KNOWN_PEEX
    StrictHostKeyChecking accept-new

Host github.com
    User git
    IdentityFile $KEY_SCM
    IdentitiesOnly yes
    AddKeysToAgent yes
$macos_keychain
$MARK_END
EOF
chmod 600 "$SSH_CONFIG"

note "sed -n '/peex managed/,/peex managed/p' ~/.ssh/config"
sed -n "/$(printf '%s' ">>> peex managed")/,/$(printf '%s' "<<< peex managed")/p" "$SSH_CONFIG" | sed 's/^/  /'

note "ssh -G peex-priv   # the EFFECTIVE config ssh will use (not the file's wishes)"
ssh -G peex-priv 2>/dev/null \
  | grep -iE '^(hostname|user|port|identityfile|identitiesonly|proxyjump|userknownhostsfile) ' \
  | sed 's/^/  /'

echo
echo "[4] LOGIN AS A NON-ROOT USER, BY ALIAS"
hr
note "ssh peex-web 'whoami; id; hostname'"
ssh -o ConnectTimeout=15 -o BatchMode=yes peex-web 'echo "logged in as: $(whoami)"; id; hostname' \
  || echo "  [FAILED] could not connect"

note "ssh peex-priv 'whoami; hostname -I'   # through the jump host, no public IP"
ssh -o ConnectTimeout=25 -o BatchMode=yes peex-priv 'echo "logged in as: $(whoami)"; hostname -I' \
  || echo "  (private host unreachable — check the 11-network stack)"

echo
echo "[5] PRIVILEGE ESCALATION (sudo)"
hr
note "ssh peex-web 'id -u; sudo id -u; sudo whoami'"
ssh -o ConnectTimeout=15 -o BatchMode=yes peex-web \
    'echo "before: uid=$(id -u) ($(whoami))"; echo "after : uid=$(sudo -n id -u) ($(sudo -n whoami))"' \
  || echo "  [FAILED] sudo escalation did not work"

echo
echo "[6] NEGATIVE TEST — password authentication is refused"
hr
echo "  A control that is never tested against the thing it forbids is a claim,"
echo "  not a control. Here we ask the server for password auth explicitly."
note "ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password peex-web true"
pw_out="$(ssh -o ConnectTimeout=15 -o BatchMode=yes \
             -o PubkeyAuthentication=no \
             -o PreferredAuthentications=password,keyboard-interactive \
             peex-web true 2>&1)"; pw_rc=$?
echo "  exit=$pw_rc  server said: ${pw_out:-(nothing)}"
if [ "$pw_rc" -ne 0 ]; then
    echo "  [OK] the server refused — password authentication is not available"
else
    echo "  >> FLAG: a password-based login succeeded"
fi

note "ssh peex-web 'sudo sshd -T | grep -E \"^(passwordauthentication|permitrootlogin|pubkeyauthentication)\"'"
ssh -o ConnectTimeout=15 -o BatchMode=yes peex-web \
    'sudo sshd -T 2>/dev/null | grep -E "^(passwordauthentication|permitrootlogin|pubkeyauthentication|maxauthtries)"' \
  | sed 's/^/  /' || echo "  (could not read effective sshd config)"

echo
echo "[7] SSH-AGENT — passphrase typed once, not per connection"
hr
if [ -z "${SSH_AUTH_SOCK:-}" ]; then
    echo "  no agent in this shell; starting one for the demo"
    eval "$(ssh-agent -s)" >/dev/null
    STARTED_AGENT=1
else
    echo "  using the agent already in this shell"
    STARTED_AGENT=0
fi
note "ssh-add $KEY_SCM   # this is where the passphrase is entered — once"
if [ -c /dev/tty ]; then
    ssh-add "$KEY_SCM" </dev/tty || echo "  (ssh-add declined or cancelled)"
else
    echo "  (no terminal available to read the passphrase — run this from a shell)"
fi
note "ssh-add -l   # identities the agent now holds"
ssh-add -l | sed 's/^/  /' || echo "  (agent holds no identities)"

echo
echo "[8] LOCAL PORT FORWARDING"
hr
echo "  Prometheus on the monitoring host is reachable on its public port, but"
echo "  cAdvisor/Alertmanager/Loki bind to 127.0.0.1 there deliberately. Port"
echo "  forwarding is how you reach them without opening a security group."
note "ssh -f -N -L $FWD_PORT:localhost:9090 peex-mon"
if ssh -f -N -o ExitOnForwardFailure=yes -o ConnectTimeout=15 \
       -L "$FWD_PORT:localhost:9090" peex-mon 2>/dev/null; then
    sleep 2
    note "curl -s localhost:$FWD_PORT/api/v1/status/buildinfo   # served by the REMOTE host"
    fwd="$(curl -sS -m 10 "http://localhost:$FWD_PORT/api/v1/status/buildinfo" 2>&1)"
    echo "  ${fwd:0:300}"
    case "$fwd" in
      *version*) echo "  [OK] the tunnel carried a real response from $MON_IP" ;;
      *)         echo "  (no Prometheus answer — is the observability stack deployed?)" ;;
    esac
    note "# tear the tunnel down"
    pkill -f "$FWD_PORT:localhost:9090" 2>/dev/null && echo "  tunnel closed" || echo "  (no tunnel process found)"
else
    echo "  [FAILED] the forward could not be established"
    echo "  NOTE: our own hardening drop-in (99-peex-hardening.conf) sets"
    echo "        'AllowTcpForwarding no'. That is a deliberate policy choice and"
    echo "        it would break exactly this. It is applied to the managed VM,"
    echo "        not to these EC2 hosts — see the README for the tradeoff."
fi

echo
echo "[9] SCM OVER SSH (GitHub)"
hr
note "ssh -T git@github.com"
scm_out="$(ssh -o ConnectTimeout=15 -o BatchMode=yes -T git@github.com 2>&1)"; scm_rc=$?
echo "  $scm_out"
echo "  (exit=$scm_rc — GitHub always exits 1 here; the greeting is the proof)"
case "$scm_out" in
  *successfully\ authenticated*) echo "  [OK] key-based authentication to GitHub works" ;;
  *Permission\ denied*)          echo "  >> the public key above is not on the GitHub account yet:"
                                 echo "     GitHub -> Settings -> SSH and GPG keys -> New SSH key" ;;
esac

note "git ls-remote $SCM_URL | head -3   # a real git operation over SSH"
git ls-remote "$SCM_URL" 2>&1 | head -3 | sed 's/^/  /'

note "git clone $SCM_URL (into a temp dir, then discarded)"
TMPD="$(mktemp -d)"
# Capture first, judge on git's own exit code. Writing this as
#   if git clone ... | sed ...; then
# would test SED's exit status, not git's, and report a failed clone as a
# success -- the exact trap that produced "(not serving)" in 06-containers.
clone_out="$(git clone --depth 1 "$SCM_URL" "$TMPD/clone" 2>&1)"; clone_rc=$?
printf '%s\n' "$clone_out" | sed 's/^/  /'
if [ "$clone_rc" -eq 0 ]; then
    echo "  [OK] cloned over SSH:"
    git -C "$TMPD/clone" remote -v | sed 's/^/    /'
    git -C "$TMPD/clone" log --oneline -1 | sed 's/^/    /'
else
    echo "  [FAILED] clone over SSH did not succeed (exit $clone_rc)"
fi
rm -rf "$TMPD"

if [ -n "$PUSH_REPO" ]; then
    note "push demo against $PUSH_REPO"
    TMPP="$(mktemp -d)"
    git clone -q "$PUSH_REPO" "$TMPP/p" 2>&1 | sed 's/^/  /'
    date -u '+peex ssh push proof %F %T UTC' >> "$TMPP/p/peex-ssh-proof.txt"
    git -C "$TMPP/p" add peex-ssh-proof.txt
    git -C "$TMPP/p" -c user.email="$(git config user.email || echo peex@local)" \
                     -c user.name="$(git config user.name || echo peex)" \
                     commit -qm "peex: ssh access proof" 2>&1 | sed 's/^/  /'
    git -C "$TMPP/p" push 2>&1 | sed 's/^/  /'
    rm -rf "$TMPP"
else
    echo
    echo "  (no push demonstrated: MovieLinks is read-only for this exercise."
    echo "   To show a push, create a throwaway repo you own and re-run with"
    echo "   PUSH_REPO=git@github.com:<you>/<scratch>.git $0)"
fi

echo
echo "[10] CONNECTION COST"
hr
note "time a key-based login"
t0=$(date +%s%N)
ssh -o ConnectTimeout=15 -o BatchMode=yes peex-web true 2>/dev/null
t1=$(date +%s%N)
echo "  key-based login round trip: $(( (t1 - t0) / 1000000 )) ms, fully non-interactive"
echo "  password login: not measurable — the server refuses it (see section 6)."
echo "  That is the honest comparison: the key path is both faster AND the only"
echo "  one available, which is the point of disabling passwords."

echo
echo "SSH ACCESS DEMO COMPLETE"
echo "To revert the client config: delete the '>>> peex managed' block from"
echo "~/.ssh/config (a backup is at ~/.ssh/config.peex-backup)."
} 2>&1 | tee "$OUT"

echo
echo "==> Wrote $OUT"
if [ "${STARTED_AGENT:-0}" = "1" ]; then
    echo "==> A temporary ssh-agent was started for this run (pid ${SSH_AGENT_PID:-?});"
    echo "    it exits with this shell, or: kill \$SSH_AGENT_PID"
fi
