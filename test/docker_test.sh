#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# docker_test.sh — Verify home restoration inside a Docker container
#
# Usage:
#   ./test/docker_test.sh                    # Test Ubuntu 24.04 (default)
#   ./test/docker_test.sh 22.04              # Test Ubuntu 22.04
#   ./test/docker_test.sh 24.04              # Test Ubuntu 24.04
#   ./test/docker_test.sh 26.04              # Test Ubuntu 26.04
#
# This builds a clean Ubuntu container and verifies that the home role
# restores files even when Ubuntu has already created skeleton dotfiles.
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
  if docker ps -aq --filter "name=^${CONTAINER_NAME}$" 2>/dev/null | grep -q .; then
    info "Cleaning up container..."
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  fi
  rm -rf "$TEST_DIR"
}

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
trap cleanup EXIT
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
      rsync \
      sudo \
      zsh \
    && rm -rf /var/lib/apt/lists/*

# Create test user matching CI
RUN useradd -m -s /bin/bash -u 2000 testuser && \
    echo 'testuser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/testuser

# User-scoped tools that must remain discoverable after restoring a captured home.
RUN mkdir -p /home/testuser/.cargo/bin /home/testuser/.local/bin && \
    printf '#!/usr/bin/env sh\nexit 0\n' > /home/testuser/.cargo/bin/cargo && \
    printf '#!/usr/bin/env sh\nexit 0\n' > /home/testuser/.local/bin/junie && \
    printf '#!/usr/bin/env sh\nexit 0\n' > /home/testuser/.local/bin/copilot && \
    chmod +x /home/testuser/.cargo/bin/cargo /home/testuser/.local/bin/junie /home/testuser/.local/bin/copilot && \
    chown -R testuser:testuser /home/testuser/.cargo /home/testuser/.local

# Ansible tmp dir
RUN mkdir -p /home/testuser/.ansible/tmp && \
    chmod 777 /home/testuser/.ansible /home/testuser/.ansible/tmp

WORKDIR /setup
COPY . .

RUN chmod -R a+rX /setup

# Create a skeleton bootstrap home
RUN mkdir -p /setup/.bootstrap/home/.ssh && \
    touch /setup/.bootstrap/home/.ssh/authorized_keys && \
    printf '%s\n' '. "\$HOME/.local/bin/env"' > /setup/.bootstrap/home/.zshrc && \
    printf '%s\n' 'export PATH="/home/sourceuser/.local/bin:/home/sourceuser/.cargo/bin:\$PATH"' > /setup/.bootstrap/home/.local-bin-env && \
    mkdir -p /setup/.bootstrap/home/.local/bin && \
    mv /setup/.bootstrap/home/.local-bin-env /setup/.bootstrap/home/.local/bin/env && \
    echo "test" > /setup/.bootstrap/home/.gitconfig && \
    chown -R root:root /setup/.bootstrap && \
    chmod 0700 /setup/.bootstrap /setup/.bootstrap/home
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
    set -euo pipefail
    ! sudo -u testuser test -r /setup/.bootstrap/home/.gitconfig
    ansible-playbook ${PLAYBOOK} \
      -i inventory.ini \
      -e 'user_name=testuser' \
      -e 'user_home=/home/testuser' \
      -e 'user_uid=2000' \
      -e 'user_gid=2000' \
      -e 'user_shell=/usr/bin/zsh' \
      -e '{\"repositories\": []}' \
      --tags home

    test -f /home/testuser/.gitconfig
    test \"\$(cat /home/testuser/.gitconfig)\" = test
    test \"\$(stat -c %U /home/testuser/.gitconfig)\" = testuser
    test -f /home/testuser/.ssh/authorized_keys
    test -f /home/testuser/.zshrc
    sudo -u testuser env \
      HOME=/home/testuser \
      USER=testuser \
      LOGNAME=testuser \
      SHELL=/usr/bin/zsh \
      PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
      zsh -lic 'command -v cargo && command -v junie && command -v copilot'
  "
log "Playbook completed"

# ---- Verify ----
header "Verifying installation"
log "Bootstrap home was restored over a pre-existing Ubuntu home"

header "Results"
log "Ubuntu ${UBUNTU_VERSION} test completed"
info "To test interactively:"
info "  docker run -it --rm dotfiles-test:${UBUNTU_VERSION} bash"
echo
