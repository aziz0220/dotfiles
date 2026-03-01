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
> "$TMP_DIR/missing-packages-installable.txt"
> "$TMP_DIR/missing-packages-unavailable.txt"

while IFS= read -r pkg; do
  candidate="$(apt-cache policy "$pkg" | awk '/Candidate:/ {c=$2} END {print c}')"
  if [ -n "$candidate" ] && [ "$candidate" != "(none)" ]; then
    echo "$pkg" >> "$TMP_DIR/missing-packages-installable.txt"
  else
    echo "$pkg" >> "$TMP_DIR/missing-packages-unavailable.txt"
  fi
done < "$TMP_DIR/missing-packages.txt"

expected_pkg_count="$(wc -l < "$TMP_DIR/expected-packages.txt")"
missing_pkg_count="$(wc -l < "$TMP_DIR/missing-packages.txt")"
installable_missing_count="$(wc -l < "$TMP_DIR/missing-packages-installable.txt")"
unavailable_missing_count="$(wc -l < "$TMP_DIR/missing-packages-unavailable.txt")"

if [ "$missing_pkg_count" -eq 0 ]; then
  pass "normalized package parity: expected=$expected_pkg_count missing=0"
else
  warn "normalized package parity: expected=$expected_pkg_count missing=$missing_pkg_count (installable=$installable_missing_count unavailable=$unavailable_missing_count)"
  if [ "$installable_missing_count" -gt 0 ]; then
    warn "installable but missing package sample: $(head -n 20 "$TMP_DIR/missing-packages-installable.txt" | tr '\n' ' ')"
  fi
  if [ "$unavailable_missing_count" -gt 0 ]; then
    warn "unavailable package sample: $(head -n 20 "$TMP_DIR/missing-packages-unavailable.txt" | tr '\n' ' ')"
  fi
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
