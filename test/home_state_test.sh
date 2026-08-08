#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

SOURCE_HOME="$TEST_DIR/source"
CAPTURE_HOME="$TEST_DIR/capture"
mkdir -p "$SOURCE_HOME/.config/nvim/.git/objects/pack"
printf 'return {}\n' > "$SOURCE_HOME/.config/nvim/init.lua"
printf 'volatile\n' > "$SOURCE_HOME/.config/nvim/.git/objects/pack/test.pack"
# shellcheck disable=SC2016  # $PATH must stay literal in the fixture
printf 'export PATH=%s/.opencode/bin:$PATH\n' "$SOURCE_HOME" > "$SOURCE_HOME/.zshrc"

ALLOW_REPO_OVERWRITE=1 INCLUDE_PRIVATE=false \
  bash "$REPO_DIR/scripts/capture_bootstrap_home.sh" "$SOURCE_HOME" "$CAPTURE_HOME" >/dev/null

test -f "$CAPTURE_HOME/.config/nvim/init.lua"
test ! -e "$CAPTURE_HOME/.config/nvim/.git"

# Shell rc files must survive restore under a different username.
if grep -q "$SOURCE_HOME" "$CAPTURE_HOME/.zshrc"; then
  printf 'FAIL: captured .zshrc still hardcodes the source home path\n' >&2
  exit 1
fi
# shellcheck disable=SC2016  # matching literal $HOME/$PATH in the captured file
grep -q '^export PATH=\$HOME/\.opencode/bin:\$PATH$' "$CAPTURE_HOME/.zshrc"

mkdir -p "$CAPTURE_HOME/.config/nvim/.git/objects/pack"
printf 'snapshot\n' > "$CAPTURE_HOME/.config/nvim/.git/objects/pack/snapshot.pack"

mapfile -t portable_entries < <(
  cd "$CAPTURE_HOME"
  find . -mindepth 1 -type d -name .git -prune -o -printf '%P\n' | sort
)

if printf '%s\n' "${portable_entries[@]}" | grep -q '/\.git\($\|/\)'; then
  printf 'FAIL: portable home parity included Git internals\n' >&2
  exit 1
fi

printf 'PASS: portable home state handling\n'