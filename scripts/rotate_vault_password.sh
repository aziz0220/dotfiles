#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# rotate_vault_password.sh — Rotate the secrets vault password
#
# Usage:
#   export OLDPASS='current-vault-password'
#   export NEWPASS='new-strong-password'
#   bash scripts/rotate_vault_password.sh
#
# Or with prompts:
#   bash scripts/rotate_vault_password.sh
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENCRYPTED_BUNDLE="${ENCRYPTED_BUNDLE:-$REPO_DIR/vault/home-secrets.tar.gz.aes256}"
DECRYPT_SCRIPT="$REPO_DIR/scripts/decrypt_home_bundle.sh"
ENCRYPT_SCRIPT="$REPO_DIR/scripts/encrypt_home_bundle.sh"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { printf "${GREEN}✓${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
err()  { printf "${RED}✗${NC} %s\n" "$1" >&2; }

cleanup() {
  rm -f "$TMP_BUNDLE" 2>/dev/null || true
}
trap cleanup EXIT

if [ ! -f "$ENCRYPTED_BUNDLE" ]; then
  err "No encrypted vault found at: $ENCRYPTED_BUNDLE"
  err "Create one first with: $ENCRYPT_SCRIPT"
  exit 1
fi

# Get old password
OLDPASS="${OLDPASS:-}"
if [ -z "$OLDPASS" ]; then
  read -r -s -p "Current vault password: " OLDPASS
  echo
  if [ -z "$OLDPASS" ]; then
    err "Password cannot be empty"
    exit 1
  fi
fi

# Verify old password works
log "Verifying current password..."
TMP_BUNDLE="$(mktemp "${TMPDIR:-/tmp}/vault-rotate.XXXXXX.tar.gz")"
if ! openssl enc -d -aes-256-cbc -salt -pbkdf2 \
  -in "$ENCRYPTED_BUNDLE" \
  -out "$TMP_BUNDLE" \
  -pass "pass:$OLDPASS" 2>/dev/null; then
  err "Failed to decrypt vault. Wrong password?"
  exit 1
fi

log "Current password verified"

# Get new password
NEWPASS="${NEWPASS:-}"
if [ -z "$NEWPASS" ]; then
  echo
  echo "Enter a new strong password for the vault."
  echo "Recommendation: 20+ characters, mixed case + numbers + symbols"
  echo
  read -r -s -p "New vault password: " NEWPASS
  echo
  read -r -s -p "Confirm new password: " NEWPASS_CONFIRM
  echo
  if [ "$NEWPASS" != "$NEWPASS_CONFIRM" ]; then
    err "Passwords do not match"
    exit 1
  fi
  if [ "${#NEWPASS}" -lt 12 ]; then
    warn "Password is shorter than 12 characters. Consider a stronger one."
  fi
fi

# Re-encrypt with new password
log "Re-encrypting vault with new password..."
export SETUP_SECRETS_PASSWORD="$NEWPASS"
if ! openssl enc -e -aes-256-cbc -salt -pbkdf2 \
  -in "$TMP_BUNDLE" \
  -out "$ENCRYPTED_BUNDLE" \
  -pass "pass:$NEWPASS" 2>/dev/null; then
  err "Failed to re-encrypt vault"
  exit 1
fi

# Verify new password works
if ! openssl enc -d -aes-256-cbc -salt -pbkdf2 \
  -in "$ENCRYPTED_BUNDLE" \
  -out /dev/null \
  -pass "pass:$NEWPASS" 2>/dev/null; then
  err "Verification of new password failed. Vault may be corrupted!"
  exit 1
fi

log "Vault password rotated successfully"
echo
echo "IMPORTANT: Update your GitHub secret:"
echo "  echo 'your-new-password' | gh secret set SETUP_SECRETS_PASSWORD --repo aziz0220/ubuntu-setup --body @-"
echo
