#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENCRYPTED_BUNDLE="${1:-$REPO_DIR/vault/home-secrets.tar.gz.aes256}"
OUTPUT_HOME_DIR="${2:-$REPO_DIR/.bootstrap/home}"
PASSWORD_ENV_VAR="${3:-SETUP_SECRETS_PASSWORD}"

if [ ! -f "$ENCRYPTED_BUNDLE" ]; then
  echo "ERROR: encrypted home bundle not found: $ENCRYPTED_BUNDLE" >&2
  exit 1
fi

if [ -z "${!PASSWORD_ENV_VAR-}" ]; then
  echo "ERROR: set $PASSWORD_ENV_VAR before running this script" >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl is required for decryption" >&2
  exit 1
fi

tmp_archive="$(mktemp "${TMPDIR:-/tmp}/bootstrap-home.XXXXXX.tar.gz")"
trap 'rm -f "$tmp_archive"' EXIT

openssl enc -d -aes-256-cbc -salt -pbkdf2 \
  -in "$ENCRYPTED_BUNDLE" \
  -out "$tmp_archive" \
  -pass env:"$PASSWORD_ENV_VAR"

rm -rf "$OUTPUT_HOME_DIR"
mkdir -p "$OUTPUT_HOME_DIR"
tar -xzf "$tmp_archive" -C "$OUTPUT_HOME_DIR"
chmod -R go-rwx "$OUTPUT_HOME_DIR" || true

echo "Decrypted bootstrap home into: $OUTPUT_HOME_DIR"
