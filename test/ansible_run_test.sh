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
  exit 1
fi
if [ "${1:-}" = "-n" ] && [ "${2:-}" = "true" ]; then
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
  DOTFILES_SKIP_FETCH=1 bash "$REPO_DIR/ansible-run" "$@" >/dev/null
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

# Identity is detected at runtime; the login shell is not. Passing the invoking
# shell as -e overrode vars/user-profile.yml, so provisioning from bash on a
# fresh machine reset the account to bash on every run.
SHELL=/bin/bash run_case
grep -q -- '-e user_name=' "$ANSIBLE_LOG" || fail "runtime identity was not passed"
if grep -q -- '-e user_shell=' "$ANSIBLE_LOG"; then
  fail "login shell must come from vars, not the invoking shell"
fi

run_case
if ! grep -qx -- '-n true' "$SUDO_LOG"; then
  fail "sudo should verify non-interactive command access without refreshing credentials"
fi
if grep -qx -- '-v' "$SUDO_LOG"; then
  fail "sudo -v should not be used because mixed PASSWD/NOPASSWD policies can still prompt"
fi

# A clone that is behind upstream must warn instead of silently provisioning
# from stale vars and a stale vault. Uses a local bare remote, never the network.
STALE_REPO="$TEST_DIR/stale"
git init -q --bare "$TEST_DIR/origin.git"
git clone -q "$TEST_DIR/origin.git" "$STALE_REPO" 2>/dev/null
git -C "$STALE_REPO" config user.email test@example.com
git -C "$STALE_REPO" config user.name test
cp "$REPO_DIR/ansible-run" "$STALE_REPO/ansible-run"
git -C "$STALE_REPO" add ansible-run
git -C "$STALE_REPO" commit -qm init
git -C "$STALE_REPO" push -q -u origin HEAD
git -C "$STALE_REPO" commit -q --allow-empty -m upstream-only
git -C "$STALE_REPO" push -q origin HEAD
git -C "$STALE_REPO" reset -q --hard HEAD~1

stale_output="$(bash "$STALE_REPO/ansible-run" 2>&1 >/dev/null || true)"
case "$stale_output" in
  *"behind upstream"*) ;;
  *) fail "stale clone did not warn: $stale_output" ;;
esac

up_to_date_output="$(DOTFILES_SKIP_FETCH=1 bash "$STALE_REPO/ansible-run" 2>&1 >/dev/null || true)"
case "$up_to_date_output" in
  *"behind upstream"*) fail "DOTFILES_SKIP_FETCH did not suppress the fetch" ;;
esac

printf 'PASS: ansible-run argument handling\n'