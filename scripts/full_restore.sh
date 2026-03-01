#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/full_restore.sh [--seed-dir /path/seed] [--repo-dir /home/aziz0220/ubuntu22-rebuild] [--repo-url git@github.com:aziz0220/ubuntu-setup.git] [--tags all] [--user aziz0220]
  ./scripts/full_restore.sh --dry-run ...

Environment:
  RECOVERY_SEED_PASSWORD   Passphrase for encrypted seed archive (if present)
  DRY_RUN                  Set to 1 to only print commands

This script:
  1) clones/fetches the repo from GitHub
  2) prepares seed directory (must be provided by user)
 3) syncs seed metadata into vars
 4) decrypts seed if encrypted and password is available
 5) runs ansible playbook with selected tags

Flags:
  --skip-update  Do not run `git pull` when repo already exists
USAGE
}

REPO_URL="${REPO_URL:-git@github.com:aziz0220/ubuntu-setup.git}"
REPO_DIR="${REPO_DIR:-/home/aziz0220/ubuntu22-rebuild}"
SEED_DIR="${SEED_DIR:-${REPO_DIR}/seed}"
RECOVERY_ROOT="${RECOVERY_ROOT:-/mnt/recovery}"
REBUILD_TAGS="${REBUILD_TAGS:-all}"
TARGET_USER="${TARGET_USER:-aziz0220}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_REPO_UPDATE="${SKIP_REPO_UPDATE:-0}"

while [[ ${1-} != "" ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --seed-dir)
      shift
      SEED_DIR="${1:?missing --seed-dir value}"
      ;;
    --recovery-root)
      shift
      RECOVERY_ROOT="${1:?missing --recovery-root value}"
      ;;
    --repo-dir)
      shift
      REPO_DIR="${1:?missing --repo-dir value}"
      ;;
    --repo-url)
      shift
      REPO_URL="${1:?missing --repo-url value}"
      ;;
    --tags)
      shift
      REBUILD_TAGS="${1:?missing --tags value}"
      ;;
    --user)
      shift
      TARGET_USER="${1:?missing --user value}"
      ;;
    --skip-update)
      SKIP_REPO_UPDATE="1"
      ;;
    --dry-run)
      DRY_RUN="1"
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
 done

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[DRY-RUN] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

log() {
  printf '%s\n' "-> $1"
}

log "Starting restore bootstrap"
log "Repository dir: $REPO_DIR"
log "Seed dir: $SEED_DIR"
log "Target user: $TARGET_USER"
log "Recovery root: $RECOVERY_ROOT"

if [[ ! -d "$REPO_DIR/.git" ]]; then
  log "Cloning setup repo"
  mkdir -p "$(dirname "$REPO_DIR")"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[DRY-RUN] git clone $REPO_URL $REPO_DIR"
  else
    git clone "$REPO_URL" "$REPO_DIR"
  fi
else
  log "Setup repo already present; updating"
  if [[ "$SKIP_REPO_UPDATE" == "1" ]]; then
    log "Skipping repo update (--skip-update)"
  else
    (cd "$REPO_DIR" && run_cmd git pull)
  fi
fi

if [[ ! -f "$SEED_DIR/home-config.tar.gz" && ! -f "$SEED_DIR/home-config.tar.gz.aes256" ]]; then
  echo "ERROR: seed not found in $SEED_DIR" >&2
  echo "Put seed files from old distro here: $SEED_DIR" >&2
  exit 1
fi

log "Syncing ansible vars from seed"
run_cmd "$REPO_DIR/collectors/sync_seed_to_vars.sh" "$SEED_DIR" "$RECOVERY_ROOT" "$TARGET_USER"

if [[ -f "$SEED_DIR/home-config.tar.gz.aes256" && ! -f "$SEED_DIR/home-config.tar.gz" ]]; then
  if [[ -n "${RECOVERY_SEED_PASSWORD-}" ]]; then
    log "Decrypting encrypted seed"
    run_cmd "$REPO_DIR/collectors/decrypt_seed.sh" "$SEED_DIR" "RECOVERY_SEED_PASSWORD"
  else
    echo "ERROR: found encrypted seed but RECOVERY_SEED_PASSWORD is not set" >&2
    exit 1
  fi
fi

if [[ "$DRY_RUN" != "1" ]]; then
  if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "ERROR: ansible-playbook not available." >&2
    echo "Install with: sudo apt-get update && sudo apt-get install -y ansible" >&2
    exit 1
  fi
else
  echo "[DRY-RUN] command -v ansible-playbook"
fi

log "Running ansible rebuild (tags: $REBUILD_TAGS)"
run_cmd "$REPO_DIR/scripts/run_rebuild.sh" "$REBUILD_TAGS" "$SEED_DIR"

log "Restore command completed"
