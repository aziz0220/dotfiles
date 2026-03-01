#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

capture_apt() {
  {
    echo "packages:"
    dpkg-query -W -f='${binary:Package}\n' \
      | sed -E 's/:(amd64|arm64|i386)$//' \
      | sort -u \
      | awk '{print "  - " $0}'
  } > "$REPO_DIR/vars/installed-packages.yml"
}

capture_snap() {
  {
    echo "snap_packages:"
    if command -v snap >/dev/null 2>&1; then
      snap list | awk 'NR>1 {print $1 "|" $4 "|" $6}' | while IFS='|' read -r name channel notes; do
        [ -z "$name" ] && continue
        echo "  - name: $name"
        if [ -n "${channel:-}" ] && [ "$channel" != "-" ]; then
          echo "    channel: $channel"
        fi
        if echo "${notes:-}" | grep -q 'classic'; then
          echo "    classic: true"
        fi
      done
    fi
  } > "$REPO_DIR/vars/snap-list.yml"
}

capture_npm_global() {
  {
    echo "npm_global_packages:"
    if [ -f "$HOME/.nvm/nvm.sh" ]; then
      zsh -ic '
        set -e
        . "$HOME/.nvm/nvm.sh"
        nvm use default >/dev/null 2>&1 || true
        npm -g ls --depth=0 --parseable 2>/dev/null
      ' \
        | sed -n '2,$p' \
        | sed -E 's|.*/node_modules/||' \
        | grep -vE '^(npm|corepack)$' \
        | sort -u \
        | awk '{print "  - \"" $0 "\""}'
    fi
  } > "$REPO_DIR/vars/npm-global.yml"
}

capture_pipx() {
  {
    echo "pipx_packages:"
    if command -v pipx >/dev/null 2>&1; then
      pipx list --json 2>/dev/null \
        | python3 -c 'import json,sys; data=json.load(sys.stdin); print("\n".join(sorted(data.get("venvs", {}).keys())))' \
        | awk 'NF {print "  - \"" $0 "\""}'
    fi
  } > "$REPO_DIR/vars/pipx.yml"
}

capture_cargo() {
  {
    echo "cargo_packages:"
    if command -v cargo >/dev/null 2>&1; then
      cargo install --list 2>/dev/null \
        | awk -F' v' '/^[A-Za-z0-9._-]+ v[0-9]/ {print $1}' \
        | sort -u \
        | awk 'NF {print "  - \"" $0 "\""}'
    fi
  } > "$REPO_DIR/vars/cargo.yml"
}

capture_gem() {
  {
    echo "gem_packages:"
    if command -v gem >/dev/null 2>&1; then
      ruby -e 'require "rubygems"; u=Gem.user_dir; puts Gem::Specification.select { |s| s.base_dir.start_with?(u) }.map(&:name).uniq.sort' \
        | sort -u \
        | awk 'NF {print "  - \"" $0 "\""}'
    fi
  } > "$REPO_DIR/vars/gem.yml"
}

capture_flatpak() {
  {
    echo "flatpak_apps:"
    if command -v flatpak >/dev/null 2>&1; then
      flatpak list --app --columns=application,origin 2>/dev/null \
        | awk 'NF {print "  - id: \"" $1 "\"\n    remote: \"" ($2=="" ? "flathub" : $2) "\""}'
    fi
  } > "$REPO_DIR/vars/flatpak.yml"
}

capture_apt
capture_snap
capture_npm_global
capture_pipx
capture_cargo
capture_gem
capture_flatpak

echo "Updated:"
echo "  - $REPO_DIR/vars/installed-packages.yml"
echo "  - $REPO_DIR/vars/snap-list.yml"
echo "  - $REPO_DIR/vars/npm-global.yml"
echo "  - $REPO_DIR/vars/pipx.yml"
echo "  - $REPO_DIR/vars/cargo.yml"
echo "  - $REPO_DIR/vars/gem.yml"
echo "  - $REPO_DIR/vars/flatpak.yml"
