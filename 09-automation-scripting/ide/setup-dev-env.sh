#!/usr/bin/env bash
# Prepare an IDE / dev environment for basic development (Trainee).
# Reports the toolchain, sets up a Python venv, and (optionally) installs
# pre-commit hooks. Run with --install to install missing pip tools.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALL=0
[ "${1:-}" = "--install" ] && INSTALL=1

check() { # $1 = cmd  $2 = hint
    if command -v "$1" >/dev/null 2>&1; then
        printf '  [ok]      %-12s %s\n' "$1" "$("$1" --version 2>&1 | head -1)"
    else
        printf '  [missing] %-12s (install: %s)\n' "$1" "$2"
    fi
}

echo "== Editor configuration present =="
ls -1 "$HERE/.editorconfig" "$HERE/.vscode/settings.json" "$HERE/.vscode/extensions.json" "$HERE/.pre-commit-config.yaml" 2>/dev/null | sed 's/^/  /'

echo
echo "== Toolchain =="
check bash       "system package"
check git        "system package"
check python3    "system package"
check shellcheck "apt install shellcheck / brew install shellcheck"
check shfmt      "brew install shfmt / go install mvdan.cc/sh/v3/cmd/shfmt@latest"
check pre-commit "pip install pre-commit"

echo
echo "== Python virtual environment =="
if [ ! -d "$HERE/.venv" ]; then
    python3 -m venv "$HERE/.venv" && echo "  created $HERE/.venv"
else
    echo "  .venv already present"
fi
# shellcheck disable=SC1091
source "$HERE/.venv/bin/activate" && echo "  activated: $(python --version)"

if [ "$INSTALL" -eq 1 ]; then
    echo
    echo "== Installing pip dev tools =="
    pip install --quiet --upgrade pip pre-commit 2>/dev/null && echo "  pre-commit installed"
    ( cd "$HERE" && pre-commit --version )
fi

echo
echo "Dev environment ready. In VS Code, open this folder and accept the"
echo "recommended extensions (.vscode/extensions.json) for lint/format on save."
