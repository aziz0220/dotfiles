#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_HOME="${1:-$HOME}"
OUTPUT_HOME_DIR="${2:-$REPO_DIR/.bootstrap/home}"
INCLUDE_PRIVATE="${INCLUDE_PRIVATE:-true}"

if [ "${ALLOW_REPO_OVERWRITE:-0}" != "1" ]; then
  cat >&2 <<'EOF'
Refusing to overwrite bootstrap home from host data.
This repository is the source of truth for bootstrap state.

If you intentionally want a one-time migration from this host, run:
  ALLOW_REPO_OVERWRITE=1 ./scripts/capture_bootstrap_home.sh
EOF
  exit 1
fi

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
  # Agent config only. The parent directories accumulate GBs of regenerable
  # state (plugin caches, session transcripts, sqlite logs) that must not enter
  # a bundle committed to a public repo -- GitHub rejects files over 100MB, and
  # transcripts are not ours to publish. Add specific config paths here.
  ".claude/settings.json"
  # Which plugins/marketplaces are installed, not the 627MB of plugin payload.
  # The new machine reinstalls them from these manifests.
  ".claude/plugins/installed_plugins.json"
  ".claude/plugins/known_marketplaces.json"
  ".codex/config.toml"
  ".codex/skills"
  ".codex/memories"
  # .local/bin deliberately omitted: every entry is an installed binary that
  # custom_tools, cargo, or npm reinstalls. Capturing it added 1.3GB.
  "bin"
)

if [ "$INCLUDE_PRIVATE" = "true" ]; then
  INCLUDE_PATHS+=(
    ".ssh"
    ".gnupg"
    ".kube"
    ".aws"
    # CLI auth tokens. Named individually, never whole directories: the parents
    # hold caches measured in tens or hundreds of MB (.docker 19M, .fly 108M,
    # .gemini 20M) around a few hundred bytes of actual credential.
    ".config/gh"
    ".config/stripe"
    ".config/netlify/config.json"
    ".config/neonctl"
    ".kaggle"
    ".huggingface"
    ".railway/config.json"
    ".docker/config.json"
    ".fly/config.yml"
    ".gemini/GEMINI.md"
    ".claude.json"
    # Agent/editor CLI logins. Without these the tools restore fully configured
    # but signed out, which is the one thing a restored machine should not
    # make you redo by hand.
    ".claude/.credentials.json"
    ".copilot/config.json"
    ".junie/secure_credentials.json"
    ".junie/settings.json"
    ".junie/trust/authentication-key"
    ".kimi-code/config.toml"
    ".local/share/opencode/auth.json"
    ".local/share/opencode/account.json"
    ".local/share/com.vercel.cli/auth.json"
    ".local/share/com.vercel.cli/config.json"
    ".config/openconnect-sso/config.toml"
    # Tailnet auth key, so a new machine joins without anyone approving a
    # browser prompt. Tailscale expires these within 90 days; when it lapses,
    # tasks/tailnet.yml prints the manual command instead of failing.
    ".config/tailscale/authkey"
    "coderefactor.pem"
  )
fi

rm -rf "$OUTPUT_HOME_DIR"
mkdir -p "$OUTPUT_HOME_DIR"

for rel in "${INCLUDE_PATHS[@]}"; do
  src="$SOURCE_HOME/$rel"
  if [ -e "$src" ]; then
    # --copy-unsafe-links dereferences symlinks pointing outside the captured
    # tree, so the bundle is self-contained. Without it, a WSL setup where
    # ~/.aws is a symlink to /mnt/c/Users/<n>/.aws captured the dangling link
    # instead of the credentials, and restoring on any non-WSL machine gave a
    # dead symlink. Relative links inside the tree stay links.
    rsync -a --relative --copy-unsafe-links --exclude='.git/' "$SOURCE_HOME/./$rel" "$OUTPUT_HOME_DIR/"
  fi
done

# Rewrite the capturing user's absolute home path so the bundle restores under
# any username. Shell rc files only: $HOME expands there, but not in the JSON
# and TOML configs that also carry absolute paths.
# ponytail: those (.claude/settings.json, .codex/config.toml) hold regenerable
# per-machine state, so leaving them stale is harmless. Revisit only if a
# non-shell config ever holds a path something actually depends on.
for rel in .zshrc .zshenv .bashrc .profile; do
  rc="$OUTPUT_HOME_DIR/$rel"
  [ -f "$rc" ] && sed -i "s|${SOURCE_HOME%/}|\$HOME|g" "$rc"
done

# Record where this bundle was captured from. JSON and TOML configs cannot use
# $HOME, so home_restore rewrites the literal path in them at restore time --
# it needs to know what to look for, and guessing from the file contents would
# be worse than being told.
printf '%s\n' "${SOURCE_HOME%/}" > "$OUTPUT_HOME_DIR/.dotfiles-captured-home"

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
