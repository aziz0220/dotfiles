#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RECOVERY_ROOT="${1:-/mnt/recovery}"
TARGET_DIR="${2:-$SCRIPT_DIR/../seed}"
USER_NAME="${3:-aziz0220}"
PASSWORD_ENV_VAR="${4:-RECOVERY_SEED_PASSWORD}"

USER_HOME="$RECOVERY_ROOT/home/$USER_NAME"
if [ ! -d "$USER_HOME" ]; then
  echo "ERROR: user home not found: $USER_HOME" >&2
  exit 1
fi

MANIFEST_DIR="$TARGET_DIR"
mkdir -p "$TARGET_DIR" "$TARGET_DIR/system" "$TARGET_DIR/metadata" "$TARGET_DIR/home"

cp_if_exists() {
  local src="$1"
  local dst="$2"
  if [ -e "$src" ]; then
    cp -f "$src" "$dst"
  fi
}

generate_if_missing() {
  local src="$1"
  local dst="$2"
  local fallback_cmd="$3"
  if [ -f "$src" ] && [ ! -s "$dst" ]; then
    cp -f "$src" "$dst"
    return
  fi
  if [ ! -s "$dst" ] && [ -n "$fallback_cmd" ]; then
    eval "$fallback_cmd" > "$dst"
  fi
}

echo "[*] Writing system metadata snapshots..."
cp_if_exists "$RECOVERY_ROOT/etc/timezone" "$TARGET_DIR/system/timezone"
cp_if_exists "$RECOVERY_ROOT/etc/default/locale" "$TARGET_DIR/system/default_locale"
cp_if_exists "$RECOVERY_ROOT/etc/wsl.conf" "$TARGET_DIR/system/wsl.conf"
cp_if_exists "$RECOVERY_ROOT/usr/share/keyrings/hashicorp-archive-keyring.gpg" "$TARGET_DIR/system/hashicorp-archive-keyring.gpg"
cp_if_exists "$SCRIPT_DIR/../roles/system_setup/files/etc_apt_sources.list" "$TARGET_DIR/system/etc_apt_sources.list"
cp_if_exists "$SCRIPT_DIR/../roles/system_setup/files/etc_apt_sources_hashicorp.list" "$TARGET_DIR/system/etc_apt_sources_hashicorp.list"
cp_if_exists "$SCRIPT_DIR/../roles/system_setup/files/etc_wsl.conf" "$TARGET_DIR/system/etc_wsl.conf"

generate_if_missing "$RECOVERY_ROOT/etc/timezone" "$TARGET_DIR/system/timezone" ""
generate_if_missing "$RECOVERY_ROOT/etc/default/locale" "$TARGET_DIR/system/default_locale" ""
generate_if_missing "$RECOVERY_ROOT/etc/wsl.conf" "$TARGET_DIR/system/wsl.conf" ""

generate_if_missing "$SCRIPT_DIR/../vars/systemd-enabled-services.txt" "$TARGET_DIR/metadata/systemd-enabled-services.txt" "awk 'NF{print}' \"$RECOVERY_ROOT/etc/systemd/system-preset/99-default.preset\" 2>/dev/null || true"

generate_if_missing "$SCRIPT_DIR/../vars/user-passwd-line.txt" "$TARGET_DIR/metadata/user-passwd-line.txt" "awk -F: -v u=\"$USER_NAME\" '\$1==u {print \$0}' \"$RECOVERY_ROOT/etc/passwd\""

generate_if_missing "$SCRIPT_DIR/../vars/group-sudo.txt" "$TARGET_DIR/metadata/group-sudo.txt" "awk -F: '\$1==\"sudo\" {print \$0}' \"$RECOVERY_ROOT/etc/group\""
generate_if_missing "$SCRIPT_DIR/../vars/group-docker.txt" "$TARGET_DIR/metadata/group-docker.txt" "awk -F: '\$1==\"docker\" {print \$0}' \"$RECOVERY_ROOT/etc/group\""

generate_if_missing "$SCRIPT_DIR/../vars/installed-packages.txt" "$TARGET_DIR/metadata/installed-packages.txt" "awk '/^Package: / {pkg=\$2} /^Status: install ok installed/ && pkg!=\"\" {print pkg}' \"$RECOVERY_ROOT/var/lib/dpkg/status\""
generate_if_missing "$SCRIPT_DIR/../vars/git-remotes.txt" "$TARGET_DIR/metadata/git-remotes.txt" ""

HOME_BUNDLE="$TARGET_DIR/home-config.tar.gz"
MANIFEST_FILE="$TARGET_DIR/home/bundle_manifest.txt"
cat > "$MANIFEST_FILE" <<'EOF2'
.bashrc
.bash_aliases
.bash_logout
.bash_profile
.profile
.zshenv
.zshrc
.tmux.conf
.dircolors
.gitconfig
.ssh
.gnupg
.config/gh
.config/git
.config/goose
.config/nvim
.config/fish
.config/uv
.config/wslu
.config/htop
.config/nextjs-nodejs
.config/create-next-app-nodejs
.config/netlify
.config/neonctl
.config/opencode
.copilot
.codex
.cursor
.oh-my-zsh
.local/bin
.local/bin/env
.local/share
.m2
.npm
.nvm
.jenv
.sdkman
.aws
.docker
.kube
.yarn
.bun
.rustup
.vscode-server
.pyenv
.opencode
EOF2

tar -czf "$HOME_BUNDLE" -C "$USER_HOME" \
  -T "$MANIFEST_FILE" \
  --ignore-failed-read

if [ -n "${!PASSWORD_ENV_VAR-}" ]; then
  ENC_FILE="${HOME_BUNDLE}.aes256"
  if command -v openssl >/dev/null 2>&1; then
    openssl enc -aes-256-cbc -salt -pbkdf2 -in "$HOME_BUNDLE" -out "$ENC_FILE" -pass env:"$PASSWORD_ENV_VAR"
    rm -f "$HOME_BUNDLE"
    echo "[+] Encrypted seed created: $ENC_FILE"
  else
    echo "[!] openssl not installed; kept unencrypted: $HOME_BUNDLE"
  fi
else
  echo "[+] Unencrypted seed created: $HOME_BUNDLE"
fi

echo "[+] Seed complete: $TARGET_DIR"
