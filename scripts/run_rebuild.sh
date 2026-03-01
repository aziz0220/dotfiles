#!/usr/bin/env bash
set -euo pipefail

PLAYBOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLAYBOOK_DIR"

REBUILD_TAGS="${1:-all}"
SEED_DIR="${2:-$PLAYBOOK_DIR/seed}"
TARGET_USER="${3:-${TARGET_USER:-aziz0220}}"
RECOVERY_ROOT="${4:-${RECOVERY_ROOT:-/mnt/recovery}}"
TARGET_HOME="${5:-${TARGET_HOME:-/home/$TARGET_USER}}"
VAULT_DIR="${VAULT_DIR:-$PLAYBOOK_DIR/vault}"
VAULT_ENCRYPTED_HOME="${VAULT_ENCRYPTED_HOME:-$VAULT_DIR/home-secrets.tar.gz.aes256}"
ANSIBLE_PLAYBOOK_FILE="${ANSIBLE_PLAYBOOK_FILE:-local.yml}"

mkdir -p "$SEED_DIR"

if [ -x "$PLAYBOOK_DIR/collectors/sync_seed_to_vars.sh" ] && [ -f "$SEED_DIR/metadata/user-passwd-line.txt" ]; then
  "$PLAYBOOK_DIR/collectors/sync_seed_to_vars.sh" "$SEED_DIR" "$RECOVERY_ROOT" "$TARGET_USER" "$TARGET_HOME"
elif [ -x "$PLAYBOOK_DIR/collectors/sync_seed_to_vars.sh" ]; then
  echo "NOTICE: seed metadata missing under $SEED_DIR/metadata; skipping auto sync and using tracked vars/." >&2
fi

if [ ! -f "$SEED_DIR/home-config.tar.gz" ] && [ -f "$SEED_DIR/home-config.tar.gz.aes256" ]; then
  if [ -n "${RECOVERY_SEED_PASSWORD-}" ]; then
    "$PLAYBOOK_DIR/collectors/decrypt_seed.sh" "$SEED_DIR" "RECOVERY_SEED_PASSWORD"
  else
    echo "NOTICE: encrypted archive exists ($SEED_DIR/home-config.tar.gz.aes256) and password is not set. Set RECOVERY_SEED_PASSWORD to auto-decrypt or run collectors/decrypt_seed.sh manually." >&2
  fi
fi

if [ ! -d "$SEED_DIR/home" ] && [ ! -f "$SEED_DIR/home-config.tar.gz" ] && [ -f "$VAULT_ENCRYPTED_HOME" ]; then
  if [ -z "${RECOVERY_SEED_PASSWORD-}" ]; then
    echo "ERROR: encrypted vault home bundle found ($VAULT_ENCRYPTED_HOME) but RECOVERY_SEED_PASSWORD is not set." >&2
    exit 1
  fi
  if ! command -v openssl >/dev/null 2>&1; then
    echo "ERROR: openssl is required to decrypt $VAULT_ENCRYPTED_HOME" >&2
    exit 1
  fi
  tmp_archive="$(mktemp "$SEED_DIR/home-secrets.XXXXXX.tar.gz")"
  trap 'rm -f "$tmp_archive"' EXIT
  echo "NOTICE: decrypting vault home bundle into seed/home ..." >&2
  openssl enc -d -aes-256-cbc -salt -pbkdf2 \
    -in "$VAULT_ENCRYPTED_HOME" \
    -out "$tmp_archive" \
    -pass env:RECOVERY_SEED_PASSWORD
  mkdir -p "$SEED_DIR/home"
  tar -xzf "$tmp_archive" -C "$SEED_DIR/home"
  rm -f "$tmp_archive"
  trap - EXIT
fi

if [ ! -d "$SEED_DIR/home" ] && [ ! -f "$SEED_DIR/home-config.tar.gz" ]; then
  echo "ERROR: no home restore source found. Expected one of:" >&2
  echo "  - $SEED_DIR/home" >&2
  echo "  - $SEED_DIR/home-config.tar.gz (or encrypted .aes256)" >&2
  echo "  - $VAULT_ENCRYPTED_HOME (with RECOVERY_SEED_PASSWORD)" >&2
  exit 1
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "NOTICE: ansible-playbook not found. Attempting to install ansible..." >&2
  if [ "$(id -u)" -eq 0 ]; then
    apt-get update
    apt-get install -y ansible
  elif command -v sudo >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y ansible
  else
    echo "ERROR: cannot auto-install ansible (no root privileges and sudo not available)." >&2
    exit 1
  fi
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ERROR: ansible-playbook is still missing after install attempt." >&2
  exit 1
fi

if [ ! -f "$PLAYBOOK_DIR/$ANSIBLE_PLAYBOOK_FILE" ]; then
  echo "ERROR: missing playbook file: $PLAYBOOK_DIR/$ANSIBLE_PLAYBOOK_FILE" >&2
  exit 1
fi

ANSIBLE_CMD=(ansible-playbook "$ANSIBLE_PLAYBOOK_FILE")
if [ "$REBUILD_TAGS" != "all" ]; then
  ANSIBLE_CMD+=(--tags "$REBUILD_TAGS")
fi

if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    ANSIBLE_CMD=(sudo "${ANSIBLE_CMD[@]}")
  else
    echo "ERROR: ansible requires root privileges and sudo is not available." >&2
    exit 1
  fi
fi

"${ANSIBLE_CMD[@]}"
