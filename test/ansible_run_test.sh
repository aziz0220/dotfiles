#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

FAKE_BIN="$TEST_DIR/bin"
ANSIBLE_LOG="$TEST_DIR/ansible.log"
SUDO_LOG="$TEST_DIR/sudo.log"
BOOTSTRAP_HOME_DIR="$TEST_DIR/bootstrap-home"

mkdir -p "$FAKE_BIN" "$BOOTSTRAP_HOME_DIR"

cat > "$FAKE_BIN/ansible-playbook" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ANSIBLE_LOG"
EOF

cat > "$FAKE_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SUDO_LOG"
if [ "${1:-}" = "-v" ]; then
  exit 0
fi
exec "$@"
EOF

chmod +x "$FAKE_BIN/ansible-playbook" "$FAKE_BIN/sudo"
export ANSIBLE_LOG SUDO_LOG
export BOOTSTRAP_HOME_DIR
export PATH="$FAKE_BIN:$PATH"

run_case() {
  : > "$ANSIBLE_LOG"
  : > "$SUDO_LOG"
  bash "$REPO_DIR/ansible-run" "$@" >/dev/null
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

run_case --ask-become-pass
grep -q -- '--ask-become-pass' "$ANSIBLE_LOG" || fail "--ask-become-pass was not forwarded"
if grep -q -- '--tags' "$ANSIBLE_LOG"; then
  fail "--ask-become-pass was treated as a tag"
fi

run_case dotfiles --check
grep -q -- '--tags dotfiles' "$ANSIBLE_LOG" || fail "tag selection was not forwarded"
grep -q -- '--check' "$ANSIBLE_LOG" || fail "extra Ansible arguments were not forwarded"

run_case
if ! grep -qx -- '-v' "$SUDO_LOG"; then
  fail "sudo should only refresh credentials, not wrap ansible-playbook"
fi

printf 'PASS: ansible-run argument handling\n'