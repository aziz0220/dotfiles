#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP_HOME_DIR="${1:-$REPO_DIR/.bootstrap/home}"
OUTPUT_FILE="${2:-$REPO_DIR/vault/home-secrets.tar.gz.aes256}"
PASSWORD_ENV_VAR="${3:-SETUP_SECRETS_PASSWORD}"

if [ ! -d "$BOOTSTRAP_HOME_DIR" ]; then
  echo "ERROR: bootstrap home directory not found: $BOOTSTRAP_HOME_DIR" >&2
  exit 1
fi

if [ -z "${!PASSWORD_ENV_VAR-}" ]; then
  echo "ERROR: set $PASSWORD_ENV_VAR before running this script" >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl is required for encryption" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"
tmp_archive="$(mktemp "${TMPDIR:-/tmp}/bootstrap-home.XXXXXX.tar.gz")"
trap 'rm -f "$tmp_archive"' EXIT

(
  cd "$BOOTSTRAP_HOME_DIR"
  tar -czf "$tmp_archive" .
)

openssl enc -aes-256-cbc -salt -pbkdf2 \
  -in "$tmp_archive" \
  -out "$OUTPUT_FILE" \
  -pass env:"$PASSWORD_ENV_VAR"

chmod 600 "$OUTPUT_FILE" || true
echo "Encrypted bundle written to: $OUTPUT_FILE"
