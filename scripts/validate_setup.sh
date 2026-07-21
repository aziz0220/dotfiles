#!/usr/bin/env bash
set -euo pipefail

PLAYBOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USER_NAME="${1:-aziz0220}"
USER_HOME="${2:-/home/$USER_NAME}"
BOOTSTRAP_HOME_DIR="${3:-$PLAYBOOK_DIR/.bootstrap/home}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

failures=0
warnings=0

pass() { printf '[PASS] %s\n' "$1"; }
info() { printf '[INFO] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; warnings=$((warnings + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; failures=$((failures + 1)); }

required_files=(
  "$PLAYBOOK_DIR/local.yml"
  "$PLAYBOOK_DIR/vars/installed-packages.yml"
  "$PLAYBOOK_DIR/vars/repos.yml"
  "$PLAYBOOK_DIR/vars/groups.yml"
  "$PLAYBOOK_DIR/vars/snap-list.yml"
  "$PLAYBOOK_DIR/vars/npm-global.yml"
  "$PLAYBOOK_DIR/vars/pipx.yml"
  "$PLAYBOOK_DIR/vars/cargo.yml"
  "$PLAYBOOK_DIR/vars/gem.yml"
  "$PLAYBOOK_DIR/vars/flatpak.yml"
  "$PLAYBOOK_DIR/vars/custom-tools.yml"
)

for path in "${required_files[@]}"; do
  if [ -e "$path" ]; then
    pass "present: $path"
  else
    fail "missing: $path"
  fi
done

if [ -d "$BOOTSTRAP_HOME_DIR" ]; then
  pass "present: $BOOTSTRAP_HOME_DIR"
else
  warn "missing bootstrap home directory: $BOOTSTRAP_HOME_DIR"
fi

echo
echo "== Package Parity (normalized) =="

awk '/^  - / {print $2}' "$PLAYBOOK_DIR/vars/installed-packages.yml" | sort -u > "$TMP_DIR/expected-packages.txt"
dpkg-query -W -f='${binary:Package}\n' | sed -E 's/:(amd64|arm64|i386)$//' | sort -u > "$TMP_DIR/installed-packages-raw.txt"
cp "$TMP_DIR/installed-packages-raw.txt" "$TMP_DIR/installed-packages-normalized.txt"
awk '/t64$/ {print substr($0, 1, length($0)-3)}' "$TMP_DIR/installed-packages-raw.txt" >> "$TMP_DIR/installed-packages-normalized.txt"
sort -u -o "$TMP_DIR/installed-packages-normalized.txt" "$TMP_DIR/installed-packages-normalized.txt"

comm -23 "$TMP_DIR/expected-packages.txt" "$TMP_DIR/installed-packages-normalized.txt" > "$TMP_DIR/missing-packages.txt"
true > "$TMP_DIR/missing-packages-installable.txt"
true > "$TMP_DIR/missing-packages-unavailable.txt"

while IFS= read -r pkg; do
  candidate="$(apt-cache policy "$pkg" | awk '/Candidate:/ {c=$2} END {print c}')"
  if [ -n "$candidate" ] && [ "$candidate" != "(none)" ]; then
    echo "$pkg" >> "$TMP_DIR/missing-packages-installable.txt"
  else
    echo "$pkg" >> "$TMP_DIR/missing-packages-unavailable.txt"
  fi
done < "$TMP_DIR/missing-packages.txt"

expected_pkg_count="$(wc -l < "$TMP_DIR/expected-packages.txt")"
installable_missing_count="$(wc -l < "$TMP_DIR/missing-packages-installable.txt")"
unavailable_missing_count="$(wc -l < "$TMP_DIR/missing-packages-unavailable.txt")"

if [ "$installable_missing_count" -eq 0 ]; then
  pass "available package parity: expected=$expected_pkg_count installable-missing=0"
else
  fail "available package parity: expected=$expected_pkg_count installable-missing=$installable_missing_count"
  fail "installable but missing package sample: $(head -n 20 "$TMP_DIR/missing-packages-installable.txt" | tr '\n' ' ')"
fi

if [ "$unavailable_missing_count" -gt 0 ]; then
  info "release-inapplicable snapshot packages: $unavailable_missing_count"
  info "release-inapplicable sample: $(head -n 20 "$TMP_DIR/missing-packages-unavailable.txt" | tr '\n' ' ')"
fi

echo
echo "== Repository Parity =="

awk -v home="$USER_HOME" '
  /^  - name:/ {
    if (name != "") print name "|" path "|" clone
    name=$0
    sub(/^  - name: "/, "", name)
    sub(/"$/, "", name)
    path=""
    clone="true"
  }
  /^    path:/ {
    path=$0
    sub(/^    path: "/, "", path)
    sub(/"$/, "", path)
    gsub(/\{\{ user_home \}\}/, home, path)
  }
  /^    clone_if_missing:/ { clone=$2 }
  END { if (name != "") print name "|" path "|" clone }
' "$PLAYBOOK_DIR/vars/repos.yml" > "$TMP_DIR/expected-repos.txt"

repo_missing_paths=0
repo_missing_git=0
while IFS='|' read -r repo_name repo_path clone_if_missing; do
  [ -z "$repo_path" ] && continue
  if [ ! -e "$repo_path" ]; then
    fail "missing repo path: $repo_name -> $repo_path"
    repo_missing_paths=$((repo_missing_paths + 1))
    continue
  fi
  if [ "$clone_if_missing" = "true" ] && [ ! -d "$repo_path/.git" ]; then
    fail "repo path exists but .git missing: $repo_name -> $repo_path"
    repo_missing_git=$((repo_missing_git + 1))
  fi
done < "$TMP_DIR/expected-repos.txt"

if [ "$repo_missing_paths" -eq 0 ] && [ "$repo_missing_git" -eq 0 ]; then
  pass "repository parity OK"
fi

echo
echo "== Custom Tool Parity =="

export HOME="$USER_HOME"
export PATH="$USER_HOME/.cargo/bin:$USER_HOME/.local/bin:$USER_HOME/.npm-global/bin:$PATH"
if [ -s "$USER_HOME/.nvm/nvm.sh" ]; then
  export NVM_DIR="$USER_HOME/.nvm"
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"
  nvm use default >/dev/null
fi

custom_tool_missing=0
while IFS=$'\t' read -r tool_name check_cmd; do
  [ -z "$tool_name" ] && continue
  if bash -c "$check_cmd" >/dev/null 2>&1; then
    pass "custom tool available: $tool_name"
  else
    fail "custom tool unavailable: $tool_name"
    custom_tool_missing=$((custom_tool_missing + 1))
  fi
done < <(
  python3 - "$PLAYBOOK_DIR/vars/custom-tools.yml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as stream:
    data = yaml.safe_load(stream) or {}

for tool in data.get("custom_tools", []):
    print(f"{tool['name']}\t{tool['check_cmd']}")
PY
)

if [ "$custom_tool_missing" -eq 0 ]; then
  pass "custom tool parity OK"
fi

echo
echo "== Login Shell Parity =="

login_shell="$(getent passwd "$USER_NAME" | awk -F: '{print $7}')"
login_shell_missing=0
if [ ! -x "$login_shell" ]; then
  fail "target login shell unavailable: ${login_shell:-unknown}"
else
  for tool_name in cargo junie copilot; do
    login_env=(
      env -i
      "HOME=$USER_HOME"
      "USER=$USER_NAME"
      "LOGNAME=$USER_NAME"
      "SHELL=$login_shell"
      TERM=dumb
      PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    )
    if [ "$(id -u)" -eq 0 ]; then
      login_env=(sudo -u "$USER_NAME" "${login_env[@]}")
    fi

    if "${login_env[@]}" "$login_shell" -lic "command -v $tool_name" >/dev/null 2>&1; then
      pass "login shell tool available: $tool_name"
    else
      fail "login shell tool unavailable: $tool_name"
      login_shell_missing=$((login_shell_missing + 1))
    fi
  done
fi

if [ "$login_shell_missing" -eq 0 ] && [ -x "$login_shell" ]; then
  pass "login shell parity OK"
fi

echo
echo "== Home Parity =="

if [ -d "$BOOTSTRAP_HOME_DIR" ]; then
  home_missing=0
  while IFS= read -r rel_path; do
    [ -z "$rel_path" ] && continue
    if [ ! -e "$USER_HOME/$rel_path" ]; then
      fail "missing home entry: $USER_HOME/$rel_path"
      home_missing=$((home_missing + 1))
    fi
  done < <(cd "$BOOTSTRAP_HOME_DIR" && find . -mindepth 1 -printf '%P\n' | sort)

  if [ "$home_missing" -eq 0 ]; then
    pass "home parity OK"
  fi
else
  warn "skipping home parity because bootstrap home directory is missing"
fi

echo
echo "== Validation Summary =="
echo "failures: $failures"
echo "warnings: $warnings"

if [ "$failures" -ne 0 ]; then
  exit 1
fi

exit 0
