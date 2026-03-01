#!/usr/bin/env bash
set -euo pipefail

SEED_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)/seed}"
PASSWORD_ENV_VAR="${2:-RECOVERY_SEED_PASSWORD}"

ENCRYPTED="$SEED_DIR/home-config.tar.gz.aes256"
PLAINTEXT="$SEED_DIR/home-config.tar.gz"

if [ ! -f "$ENCRYPTED" ]; then
  echo "No encrypted archive at $ENCRYPTED" >&2
  exit 1
fi

if [ -z "${!PASSWORD_ENV_VAR-}" ]; then
  echo "Set $PASSWORD_ENV_VAR before running this script" >&2
  exit 1
fi

openssl enc -d -aes-256-cbc -salt -pbkdf2 -in "$ENCRYPTED" -out "$PLAINTEXT" -pass env:"$PASSWORD_ENV_VAR"
echo "Decrypted: $PLAINTEXT"
