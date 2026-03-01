#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEED_DIR="${1:-$SCRIPT_DIR/../seed}"
OUTPUT_FILE="${2:-$SCRIPT_DIR/../vault/home-secrets.tar.gz.aes256}"
PASSWORD_ENV_VAR="${3:-RECOVERY_SEED_PASSWORD}"

SEED_HOME_DIR="$SEED_DIR/home"

if [ ! -d "$SEED_HOME_DIR" ]; then
  echo "ERROR: missing seed home directory: $SEED_HOME_DIR" >&2
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
tmp_archive="$(mktemp "${TMPDIR:-/tmp}/home-secrets.XXXXXX.tar.gz")"
trap 'rm -f "$tmp_archive"' EXIT

(
  cd "$SEED_HOME_DIR"
  tar -czf "$tmp_archive" .
)

openssl enc -aes-256-cbc -salt -pbkdf2 \
  -in "$tmp_archive" \
  -out "$OUTPUT_FILE" \
  -pass env:"$PASSWORD_ENV_VAR"

chmod 600 "$OUTPUT_FILE" || true
echo "Encrypted home bundle created: $OUTPUT_FILE"
