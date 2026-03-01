#!/usr/bin/env bash
set -euo pipefail

PLAYBOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SEED_DIR="${1:-$PLAYBOOK_DIR/seed}"
RECOVERY_ROOT="${2:-/mnt/recovery}"
USER_NAME="${3:-aziz0220}"

failures=0
warnings=0

pass() { printf '[PASS] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; warnings=$((warnings + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; failures=$((failures + 1)); }

count_yaml_items() {
  local yaml_file="$1"
  local key="$2"
  awk -v k="$key" '
    $0 ~ ("^" k ":") {f=1; next}
    f && $0 ~ /^  - / {c++}
    END {print c+0}
  ' "$yaml_file" 2>/dev/null || echo 0
}

count_seed_repo_paths() {
  local repo_file="$1"
  grep -c '^repo: ' "$repo_file" 2>/dev/null || echo 0
}

if [ ! -d "$SEED_DIR" ]; then
  echo "ERROR: seed directory not found: $SEED_DIR" >&2
  exit 2
fi

if [ ! -d "$RECOVERY_ROOT" ]; then
  echo "ERROR: recovery root not found: $RECOVERY_ROOT" >&2
  exit 2
fi

if [ ! -d "$RECOVERY_ROOT/home/$USER_NAME" ]; then
  echo "ERROR: recovery user home not found: $RECOVERY_ROOT/home/$USER_NAME" >&2
  exit 2
fi

while IFS= read -r link_path; do
  link_target="$(readlink "$link_path" 2>/dev/null || true)"
  if [ -n "$link_target" ] && [[ "$link_target" = /* ]] && [[ "$link_target" != "$RECOVERY_ROOT/home/$USER_NAME"* ]]; then
    warn "external symlink in source home may not be portable: ${link_path#$RECOVERY_ROOT/home/$USER_NAME/} -> $link_target"
  fi
done < <(find "$RECOVERY_ROOT/home/$USER_NAME" -mindepth 1 -maxdepth 1 -type l 2>/dev/null)

echo "== Validation Inputs =="
echo "repo: $PLAYBOOK_DIR"
echo "seed: $SEED_DIR"
echo "recovery: $RECOVERY_ROOT"
echo "user: $USER_NAME"
echo

required_seed_files=(
  "$SEED_DIR/home"
  "$SEED_DIR/metadata/installed-packages.txt"
  "$SEED_DIR/metadata/systemd-enabled-services.txt"
  "$SEED_DIR/metadata/git-remotes.txt"
  "$SEED_DIR/metadata/user-passwd-line.txt"
)

for path in "${required_seed_files[@]}"; do
  if [ -e "$path" ]; then
    pass "present: $path"
  else
    fail "missing: $path"
  fi
done

required_var_files=(
  "$PLAYBOOK_DIR/vars/user-profile.yml"
  "$PLAYBOOK_DIR/vars/system-locale.yml"
  "$PLAYBOOK_DIR/vars/installed-packages.yml"
  "$PLAYBOOK_DIR/vars/systemd-enabled-services.yml"
  "$PLAYBOOK_DIR/vars/repos.yml"
  "$PLAYBOOK_DIR/vars/runtimes.yml"
)

for path in "${required_var_files[@]}"; do
  if [ -f "$path" ]; then
    pass "present: $path"
  else
    fail "missing: $path"
  fi
done

src_pkg_count="$(grep -c '^Package: ' "$RECOVERY_ROOT/var/lib/dpkg/status" 2>/dev/null || echo 0)"
seed_pkg_count="$(wc -l < "$SEED_DIR/metadata/installed-packages.txt" 2>/dev/null || echo 0)"
vars_pkg_count="$(count_yaml_items "$PLAYBOOK_DIR/vars/installed-packages.yml" "packages")"

if [ "$src_pkg_count" = "$seed_pkg_count" ] && [ "$seed_pkg_count" = "$vars_pkg_count" ]; then
  pass "package parity: source=$src_pkg_count seed=$seed_pkg_count vars=$vars_pkg_count"
else
  fail "package mismatch: source=$src_pkg_count seed=$seed_pkg_count vars=$vars_pkg_count"
fi

src_service_count="$(find "$RECOVERY_ROOT/etc/systemd/system" -type l -printf '%f\n' 2>/dev/null | sort -u | wc -l | tr -d ' ')"
seed_service_count="$(wc -l < "$SEED_DIR/metadata/systemd-enabled-services.txt" 2>/dev/null || echo 0)"
vars_service_count="$(count_yaml_items "$PLAYBOOK_DIR/vars/systemd-enabled-services.yml" "systemd_services")"

if [ "$src_service_count" = "$seed_service_count" ] && [ "$seed_service_count" = "$vars_service_count" ]; then
  pass "service parity: source=$src_service_count seed=$seed_service_count vars=$vars_service_count"
else
  fail "service mismatch: source=$src_service_count seed=$seed_service_count vars=$vars_service_count"
fi

src_repo_count="$(find "$RECOVERY_ROOT/home/$USER_NAME" -type d -name .git -prune 2>/dev/null | wc -l | tr -d ' ')"
seed_repo_count="$(count_seed_repo_paths "$SEED_DIR/metadata/git-remotes.txt")"
vars_repo_count="$(count_yaml_items "$PLAYBOOK_DIR/vars/repos.yml" "repositories")"

if [ "$src_repo_count" = "$seed_repo_count" ]; then
  pass "repo discovery parity: source=$src_repo_count seed=$seed_repo_count"
else
  fail "repo discovery mismatch: source=$src_repo_count seed=$seed_repo_count"
fi

if [ "$vars_repo_count" -ge "$seed_repo_count" ]; then
  pass "vars repo coverage: vars=$vars_repo_count seed=$seed_repo_count"
else
  fail "vars repo coverage too low: vars=$vars_repo_count seed=$seed_repo_count"
fi

src_ssh_files="$(find "$RECOVERY_ROOT/home/$USER_NAME/.ssh" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
seed_ssh_files="$(find "$SEED_DIR/home/.ssh" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$src_ssh_files" = "$seed_ssh_files" ]; then
  pass "ssh file parity: source=$src_ssh_files seed=$seed_ssh_files"
else
  fail "ssh file mismatch: source=$src_ssh_files seed=$seed_ssh_files"
fi

src_gnupg_files="$(find "$RECOVERY_ROOT/home/$USER_NAME/.gnupg" -maxdepth 2 -type f 2>/dev/null | wc -l | tr -d ' ')"
seed_gnupg_files="$(find "$SEED_DIR/home/.gnupg" -maxdepth 2 -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$src_gnupg_files" = "$seed_gnupg_files" ]; then
  pass "gnupg file parity: source=$src_gnupg_files seed=$seed_gnupg_files"
else
  fail "gnupg file mismatch: source=$src_gnupg_files seed=$seed_gnupg_files"
fi

src_config_entries="$(find "$RECOVERY_ROOT/home/$USER_NAME/.config" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
seed_config_entries="$(find "$SEED_DIR/home/.config" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
if [ "$src_config_entries" = "$seed_config_entries" ]; then
  pass "config tree parity: source=$src_config_entries seed=$seed_config_entries"
else
  fail "config tree mismatch: source=$src_config_entries seed=$seed_config_entries"
fi

critical_files=(
  "$SEED_DIR/home/.zshrc"
  "$SEED_DIR/home/.bashrc"
  "$SEED_DIR/home/.gitconfig"
  "$SEED_DIR/home/.oh-my-zsh"
)

for path in "${critical_files[@]}"; do
  if [ -e "$path" ]; then
    pass "critical present: $path"
  else
    fail "critical missing: $path"
  fi
done

if bash -n "$PLAYBOOK_DIR"/collectors/*.sh "$PLAYBOOK_DIR"/scripts/*.sh; then
  pass "bash syntax checks passed"
else
  fail "bash syntax checks failed"
fi

if command -v ansible-playbook >/dev/null 2>&1; then
  if (cd "$PLAYBOOK_DIR" && ansible-playbook --syntax-check site.yml >/dev/null); then
    pass "ansible syntax check passed"
  else
    fail "ansible syntax check failed"
  fi
else
  warn "ansible-playbook not found; skipped ansible syntax check"
fi

echo
echo "== Validation Summary =="
echo "failures: $failures"
echo "warnings: $warnings"

if [ "$failures" -ne 0 ]; then
  exit 1
fi

exit 0
