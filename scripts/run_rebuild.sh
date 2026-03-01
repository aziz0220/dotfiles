#!/usr/bin/env bash
set -euo pipefail

PLAYBOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLAYBOOK_DIR"

REBUILD_TAGS="${1:-all}"
SEED_DIR="${2:-$PLAYBOOK_DIR/seed}"

if [ ! -d "$SEED_DIR" ]; then
  echo "ERROR: seed directory does not exist: $SEED_DIR" >&2
  echo "Run collectors/build_recovery_seed.sh first." >&2
  exit 1
fi

if [ -x "$PLAYBOOK_DIR/collectors/sync_seed_to_vars.sh" ]; then
  "$PLAYBOOK_DIR/collectors/sync_seed_to_vars.sh" "$SEED_DIR"
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ERROR: ansible-playbook not found. Install Ansible first: apt-get update && apt-get install -y ansible" >&2
  exit 1
fi

if [ "$REBUILD_TAGS" = "all" ]; then
  ansible-playbook site.yml
else
  ansible-playbook site.yml --tags "$REBUILD_TAGS"
fi
