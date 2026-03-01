#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_HOME="${1:-$HOME}"
OUTPUT_HOME_DIR="${2:-$REPO_DIR/.bootstrap/home}"
INCLUDE_PRIVATE="${INCLUDE_PRIVATE:-true}"

if [ ! -d "$SOURCE_HOME" ]; then
  echo "ERROR: source home directory not found: $SOURCE_HOME" >&2
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "ERROR: rsync is required for capture" >&2
  exit 1
fi

declare -a INCLUDE_PATHS=(
  ".zshrc"
  ".zshenv"
  ".profile"
  ".bashrc"
  ".bash_logout"
  ".tmux.conf"
  ".gitconfig"
  ".gitignore"
  ".npmrc"
  ".yarnrc"
  ".p10k.zsh"
  ".config/nvim"
  ".config/ghostty"
  ".config/kitty"
  ".config/alacritty"
  ".config/tmux"
  ".oh-my-zsh/custom"
  ".claude"
  ".codex"
  ".local/bin"
  "bin"
)

if [ "$INCLUDE_PRIVATE" = "true" ]; then
  INCLUDE_PATHS+=(
    ".ssh"
    ".gnupg"
    ".kube"
    ".aws"
  )
fi

rm -rf "$OUTPUT_HOME_DIR"
mkdir -p "$OUTPUT_HOME_DIR"

for rel in "${INCLUDE_PATHS[@]}"; do
  src="$SOURCE_HOME/$rel"
  if [ -e "$src" ]; then
    rsync -a --relative "$SOURCE_HOME/./$rel" "$OUTPUT_HOME_DIR/"
  fi
done

# Remove host-specific or runtime artifacts that should not be replicated.
rm -f "$OUTPUT_HOME_DIR/.ssh/known_hosts" "$OUTPUT_HOME_DIR/.ssh/known_hosts.old" || true
find "$OUTPUT_HOME_DIR/.gnupg" -maxdepth 1 -type s -delete 2>/dev/null || true
find "$OUTPUT_HOME_DIR/.gnupg" -name '*.lock' -delete 2>/dev/null || true

if [ -d "$OUTPUT_HOME_DIR/.ssh" ]; then
  chmod 700 "$OUTPUT_HOME_DIR/.ssh" || true
  find "$OUTPUT_HOME_DIR/.ssh" -type f -name '*.pub' -exec chmod 644 {} + 2>/dev/null || true
  find "$OUTPUT_HOME_DIR/.ssh" -type f ! -name '*.pub' -exec chmod 600 {} + 2>/dev/null || true
fi

if [ -d "$OUTPUT_HOME_DIR/.gnupg" ]; then
  chmod 700 "$OUTPUT_HOME_DIR/.gnupg" || true
fi

chmod -R go-rwx "$OUTPUT_HOME_DIR" || true

echo "Captured bootstrap home to: $OUTPUT_HOME_DIR"
du -sh "$OUTPUT_HOME_DIR" || true
