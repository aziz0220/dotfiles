#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# docker_test.sh — Run full provisioning inside a Docker container
#
# Usage:
#   ./test/docker_test.sh                    # Test Ubuntu 24.04 (default)
#   ./test/docker_test.sh 22.04              # Test Ubuntu 22.04
#   ./test/docker_test.sh 24.04              # Test Ubuntu 24.04
#
# This builds a clean Ubuntu container, installs Ansible, and runs the
# full playbook against it — the same way CI does, but locally.
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UBUNTU_VERSION="${1:-24.04}"
CONTAINER_NAME="dotfiles-test-$(date +%s)"
PLAYBOOK="${ANSIBLE_PLAYBOOK_FILE:-local.yml}"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()  { printf "${GREEN}✓${NC} %s\n" "$1"; }
info() { printf "${CYAN}ℹ${NC} %s\n" "$1"; }
err()  { printf "${RED}✗${NC} %s\n" "$1" >&2; }
header() { printf "\n${BOLD}%s${NC}\n" "$1"; }

cleanup() {
  if docker ps -q --filter "name=$CONTAINER_NAME" 2>/dev/null | grep -q .; then
    info "Cleaning up container..."
    docker kill "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ---- Pre-flight checks ----
header "Pre-flight checks"

if ! command -v docker &>/dev/null; then
  err "Docker is required. Install it first."
  exit 1
fi

info "Ubuntu version: $UBUNTU_VERSION"
info "Playbook: $PLAYBOOK"
info "Repo: $REPO_DIR"

# ---- Build a test image with a non-root user ----
header "Building test environment"

TEST_DIR="$(mktemp -d)"
cat > "$TEST_DIR/Dockerfile" <<DOCKERFILE
FROM ubuntu:${UBUNTU_VERSION}

# Prevent tzdata interactive prompt
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && \
    apt-get install -y -qq \
      ansible \
      git \
      curl \
      tar \
      unzip \
      ca-certificates \
      openssl \
      sudo \
    && rm -rf /var/lib/apt/lists/*

# Create test user matching CI
RUN useradd -m -s /bin/bash -u 2000 testuser && \
    echo 'testuser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/testuser

# Ansible tmp dir
RUN mkdir -p /home/testuser/.ansible/tmp && \
    chmod 777 /home/testuser/.ansible /home/testuser/.ansible/tmp

WORKDIR /setup
COPY . .

RUN chmod -R a+rX /setup

# Create a skeleton bootstrap home
RUN mkdir -p /setup/.bootstrap/home/.ssh && \
    touch /setup/.bootstrap/home/.ssh/authorized_keys && \
    echo "test" > /setup/.bootstrap/home/.zshrc && \
    echo "test" > /setup/.bootstrap/home/.gitconfig
DOCKERFILE

info "Building Docker image for Ubuntu ${UBUNTU_VERSION}..."
docker build -t "dotfiles-test:${UBUNTU_VERSION}" -f "$TEST_DIR/Dockerfile" "$REPO_DIR"
log "Image built"

# ---- Run provisioning ----
header "Running playbook"

docker run --name "$CONTAINER_NAME" \
  -e "HOME=/home/testuser" \
  -e "CI=true" \
  "dotfiles-test:${UBUNTU_VERSION}" \
  bash -c "
    set -e
    ansible-playbook ${PLAYBOOK} \
      -i inventory.ini \
      -e 'user_name=testuser' \
      -e 'user_home=/home/testuser' \
      -e 'user_uid=2000' \
      -e 'user_gid=2000' \
      -e 'user_shell=/bin/bash'
  "
log "Playbook completed"

# ---- Verify ----
header "Verifying installation"

docker run --name "${CONTAINER_NAME}-verify" \
  -e "HOME=/home/testuser" \
  "dotfiles-test:${UBUNTU_VERSION}" \
  bash -c "
    set -x
    echo '=== System ==='
    cat /etc/os-release | head -2
    echo '=== Shell ==='
    su - testuser -c 'zsh --version' 2>/dev/null || echo 'zsh not installed'
    echo '=== Git ==='
    git --version
    echo '=== Curl ==='
    curl --version | head -1
    echo '=== GitHub CLI ==='
    gh --version | head -1 || echo 'gh not installed'
    echo '=== Dotfiles ==='
    ls -la /home/testuser/ 2>/dev/null | head -10
  " || true

# Clean up verify container
docker rm "${CONTAINER_NAME}-verify" 2>/dev/null || true

header "Results"
log "Ubuntu ${UBUNTU_VERSION} test completed"
info "To test interactively:"
info "  docker run -it --rm dotfiles-test:${UBUNTU_VERSION} bash"
echo
