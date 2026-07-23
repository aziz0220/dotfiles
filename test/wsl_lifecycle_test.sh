#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_SCRIPT="$REPO_DIR/test/wsl_lifecycle_test.ps1"

if command -v pwsh >/dev/null 2>&1; then
  exec pwsh -NoProfile -File "$TEST_SCRIPT"
fi

if command -v powershell.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
  exec powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$(wslpath -w "$TEST_SCRIPT")"
fi

printf 'SKIP: PowerShell is unavailable; WSL lifecycle test not run\n'
