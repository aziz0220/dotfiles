#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# docker_sandbox.sh — Provision a throwaway container with the REAL setup
#
# Unlike test/docker_test.sh (which uses a fake skeleton home), this restores
# your actual vault and drops you into a shell as yourself.
#
# Usage:
#   ./scripts/docker_sandbox.sh              # full provision (slow: ~1600 apt packages)
#   ./scripts/docker_sandbox.sh home         # dotfiles + secrets only (fast)
#   ./scripts/docker_sandbox.sh core,node    # any tag set
#   UBUNTU_VERSION=22.04 ./scripts/docker_sandbox.sh
#
# Needs SETUP_SECRETS_PASSWORD unless .bootstrap/home/ is already decrypted.
# Re-enter a running sandbox with: docker exec -it dotfiles-sandbox su - <user>
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04}"
TAGS="${1:-all}"
NAME="${SANDBOX_NAME:-dotfiles-sandbox}"

command -v docker >/dev/null || { echo "ERROR: docker is required" >&2; exit 1; }

if [ ! -d "$REPO_DIR/.bootstrap/home" ] && [ -z "${SETUP_SECRETS_PASSWORD-}" ]; then
  echo "ERROR: set SETUP_SECRETS_PASSWORD (or decrypt .bootstrap/home first)" >&2
  exit 1
fi

USER_NAME="$(sed -n 's/^user_name: //p' "$REPO_DIR/vars/user-profile.yml")"

docker rm -f "$NAME" >/dev/null 2>&1 || true

echo "→ Starting ubuntu:${UBUNTU_VERSION} sandbox '$NAME'"
docker run -d --name "$NAME" \
  -e "SETUP_SECRETS_PASSWORD=${SETUP_SECRETS_PASSWORD-}" \
  "ubuntu:${UBUNTU_VERSION}" sleep infinity >/dev/null

# ponytail: docker cp, not -v. Docker Desktop reaches this WSL distro over a
# Windows pipe and cannot see its paths, so a bind mount silently comes up empty.
echo "→ Copying repo into container"
docker cp "$REPO_DIR/." "$NAME:/setup"

docker exec "$NAME" bash -c '
  set -euo pipefail
  export DEBIAN_FRONTEND=noninteractive

  apt-get update -qq
  apt-get install -y -qq ansible git curl tar unzip ca-certificates openssl rsync sudo zsh

  # Ubuntu 24.04+ ships a stock uid-1000 "ubuntu" user that collides with yours.
  userdel -r ubuntu 2>/dev/null || true

  cd /setup
  [ -d .bootstrap/home ] || bash scripts/decrypt_home_bundle.sh

  # No -e overrides: vars/user-profile.yml already carries the real identity.
  ansible-playbook local.yml -i inventory.ini '"$([ "$TAGS" = all ] || echo "--tags $TAGS")"'
'

echo
echo "✓ Sandbox ready. Enter it with:"
echo "    docker exec -it $NAME su - $USER_NAME"
echo "  Destroy it with:"
echo "    docker rm -f $NAME"

[ -t 0 ] && exec docker exec -it "$NAME" su - "$USER_NAME"
