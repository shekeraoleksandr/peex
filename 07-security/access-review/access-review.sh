#!/usr/bin/env bash
# Prepare user access data for a least-privilege review (Trainee).
#
# Inventories local accounts and their privileges and flags items a security
# owner should review. Read-only; run with sudo for the password-state and
# authorized_keys checks.
#
# WHY THERE ARE TWO CODE PATHS
# ----------------------------
# The first version of this script read /etc/passwd, /etc/group and /etc/shadow
# directly. That is correct on Linux and quietly WRONG on macOS, which is where
# it first ran:
#
#   * /etc/passwd on macOS lists only a handful of system accounts. Real user
#     accounts live in Open Directory, so the review silently skipped every
#     human being on the machine -- the opposite of what an access review is
#     for, and it looked like a clean result.
#   * The comment header of /etc/passwd has no ':' separators, so awk saw empty
#     fields, decided the "shell" was not nologin, and printed nine comment
#     lines as if they were login-capable accounts.
#   * getent does not exist on macOS, so the privileged-groups section printed
#     nothing at all rather than reporting that it could not check.
#   * /etc/shadow does not exist on macOS either, and the fallback text told
#     you to re-run with sudo -- advice that can never help, and which you
#     would keep following.
#
# An access review that under-reports is worse than one that errors out, so the
# platform-specific lookups now live behind four functions with a real
# implementation per OS, and anything that cannot be checked says so.
set -uo pipefail

OUT_JSON="${1:-}"                      # optional machine-readable report
OS="${FORCE_OS:-$(uname -s)}"          # FORCE_OS is for testing the other path

hr() { printf '%s\n' "-------------------------------------------------------------"; }

# --- platform layer ---------------------------------------------------------
# Every function prints one record per line; callers stay OS-agnostic.

# list_accounts -> "user:uid:gid:home:shell"
list_accounts() {
    case "$OS" in
      Darwin)
        # Open Directory is the source of truth. Four flat lists, joined by
        # name, is far faster than one `dscl -read` per account.
        { dscl . -list /Users UniqueID          | sed 's/^/U /'
          dscl . -list /Users PrimaryGroupID    | sed 's/^/G /'
          dscl . -list /Users NFSHomeDirectory  | sed 's/^/H /'
          dscl . -list /Users UserShell         | sed 's/^/S /'
        } 2>/dev/null | awk '
            { key=$1; name=$2; $1=""; $2=""; sub(/^ +/,""); val=$0
              if (key=="U") uid[name]=val
              else if (key=="G") gid[name]=val
              else if (key=="H") home[name]=val
              else if (key=="S") sh[name]=val
              seen[name]=1 }
            END { for (n in seen)
                    printf "%s:%s:%s:%s:%s\n", n, uid[n], gid[n], home[n], sh[n] }
        ' | sort -t: -k2 -n
        ;;
      *)
        # Skip comments and malformed lines -- NF==7 is what makes a passwd
        # entry an entry.
        awk -F: '/^[^#]/ && NF==7 {printf "%s:%s:%s:%s:%s\n",$1,$3,$4,$6,$7}' /etc/passwd
        ;;
    esac
}

# group_members <group> -> space-separated member list, or the literal string
# "<group does not exist>" / "<unreadable>"
group_members() {
    local g="$1"
    case "$OS" in
      Darwin)
        local out
        out="$(dscl . -read "/Groups/$g" GroupMembership 2>/dev/null)" || {
            echo "<group does not exist>"; return; }
        [ -n "$out" ] || { echo "<no direct members>"; return; }
        printf '%s\n' "$out" | tr '\n' ' ' | sed 's/^GroupMembership: *//; s/ *$//'
        ;;
      *)
        if getent group "$g" >/dev/null 2>&1; then
            local m; m="$(getent group "$g" | awk -F: '{print $4}')"
            echo "${m:-<no direct members>}"
        else
            echo "<group does not exist>"
        fi
        ;;
    esac
}

# password_state <user> -> human-readable state
password_state() {
    local u="$1"
    case "$OS" in
      Darwin)
        local aa
        aa="$(dscl . -read "/Users/$u" AuthenticationAuthority 2>/dev/null | tr '\n' ' ')" || aa=""
        case "$aa" in
          *DisabledUser*)  echo "DISABLED" ;;
          *ShadowHash*)    echo "password set" ;;
          "")              echo "no authentication authority (no interactive login)" ;;
          *)               echo "other (${aa#AuthenticationAuthority: })" ;;
        esac
        ;;
      *)
        if [ -r /etc/shadow ]; then
            local h; h="$(awk -F: -v u="$u" '$1==u{print $2}' /etc/shadow)"
            case "$h" in
              "")      echo "EMPTY PASSWORD" ;;
              '!'*|'*') echo "locked / no password login" ;;
              *)       echo "password set" ;;
            esac
        else
            echo "<needs root>"
        fi
        ;;
    esac
}

password_source() {
    case "$OS" in
      Darwin) echo "Open Directory (dscl AuthenticationAuthority)" ;;
      *)      echo "/etc/shadow" ;;
    esac
}

# --- report -----------------------------------------------------------------
echo "==============================================================="
echo " User access review  —  host: $(hostname)  —  $(date -u '+%F %T UTC')"
echo " platform: $OS        running as: $(id -un)$([ "$(id -u)" -eq 0 ] && echo ' (root)')"
echo "==============================================================="

if [ "$OS" = "Darwin" ] && ! command -v dscl >/dev/null 2>&1; then
    echo "ERROR: macOS detected but dscl is missing; account data is unreadable." >&2
    exit 1
fi

echo "[1] Login-capable accounts (shell is not nologin/false)"
hr
login_accounts=""
while IFS=: read -r user uid gid home shell; do
    case "$shell" in
      *nologin|*false|"") continue ;;
    esac
    printf "  %-20s uid=%-6s gid=%-6s shell=%-14s home=%s\n" "$user" "$uid" "$gid" "$shell" "$home"
    login_accounts="$login_accounts $user"
done < <(list_accounts)
[ -n "$login_accounts" ] || echo "  (none found — this is suspicious, not clean; check the platform layer)"

echo
echo "[2] UID 0 accounts (must be ONLY root)"
hr
uid0="$(list_accounts | awk -F: '$2==0 {print $1}')"
if [ -z "$uid0" ]; then
    echo "  (none found — expected at least root; account lookup may have failed)"
else
    printf '%s\n' "$uid0" | sed 's/^/  /'
    if printf '%s\n' "$uid0" | grep -qv '^root$'; then
        echo "  >> FLAG: extra UID 0 account(s) found — privilege escalation risk"
    fi
fi

echo
echo "[3] Members of privileged groups (sudo / wheel / admin / root)"
hr
for g in sudo wheel admin root; do
    printf "  %-8s : %s\n" "$g" "$(group_members "$g")"
done
if [ "$OS" = "Darwin" ]; then
    echo
    echo "  NOTE: on macOS the 'admin' group is the one that matters — /etc/sudoers"
    echo "        grants it '%admin ALL=(ALL) ALL' (see section 6), so every member"
    echo "        listed above has full root via sudo."
fi

echo
echo "[4] Accounts with SSH authorized_keys"
hr
found=0
while IFS=: read -r user uid gid home shell; do
    [ -n "$home" ] && [ -d "$home" ] || continue
    ak="$home/.ssh/authorized_keys"
    if [ -f "$ak" ]; then
        if [ -r "$ak" ]; then
            n="$(grep -cvE '^[[:space:]]*(#|$)' "$ak" 2>/dev/null)" || n="?"
        else
            n="unreadable"
        fi
        printf "  %-20s keys=%-4s shell=%s\n" "$user" "$n" "$shell"
        found=1
    fi
done < <(list_accounts)
if [ "$found" -eq 0 ]; then
    if [ "$(id -u)" -eq 0 ]; then
        echo "  (no authorized_keys files exist under any account's home)"
    else
        echo "  (none found — other users' homes are unreadable; re-run with sudo)"
    fi
fi

echo
echo "[5] Password / lock status  — source: $(password_source)"
hr
if [ "$OS" != "Darwin" ] && [ ! -r /etc/shadow ]; then
    echo "  (no read access to /etc/shadow — run: sudo $0)"
else
    for u in $login_accounts; do
        state="$(password_state "$u")"
        case "$state" in
          "EMPTY PASSWORD") printf "  >> FLAG: %-18s EMPTY PASSWORD\n" "$u" ;;
          *)                printf "  %-20s %s\n" "$u" "$state" ;;
        esac
    done
fi

echo
echo "[6] Sudoers NOPASSWD / broad grants"
hr
if [ -r /etc/sudoers ]; then
    grep -rEn 'NOPASSWD|ALL[[:space:]]*=[[:space:]]*\(ALL' /etc/sudoers /etc/sudoers.d/ 2>/dev/null \
        | sed 's/^/  /' || echo "  (none)"
else
    echo "  (no read access to sudoers — run with sudo)"
fi

echo
echo "Review complete. Share this output with the security owner and confirm"
echo "each login-capable / privileged account still needs its access (least privilege)."

# --- optional JSON summary --------------------------------------------------
if [ -n "$OUT_JSON" ]; then
    login_csv="$(printf '%s' "${login_accounts# }" | tr ' ' ',')"
    admin_members="$(group_members admin)"
    sudo_members="$(group_members sudo)"
    python3 - "$OUT_JSON" "$(hostname)" "$OS" "$login_csv" "$admin_members" "$sudo_members" <<'PY'
import json, sys, datetime
path, host, osname, login_csv, admin_m, sudo_m = sys.argv[1:7]
json.dump({
    "host": host,
    "platform": osname,
    "generated": datetime.datetime.now(datetime.timezone.utc)
                  .strftime("%Y-%m-%dT%H:%M:%SZ"),
    "login_users": [u for u in login_csv.split(",") if u],
    "admin_group": admin_m,
    "sudo_group": sudo_m,
}, open(path, "w"), indent=2)
PY
    echo "JSON summary -> $OUT_JSON"
fi
