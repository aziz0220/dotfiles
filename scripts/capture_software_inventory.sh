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

capture_apt
capture_snap
capture_npm_global

echo "Updated:"
echo "  - $REPO_DIR/vars/installed-packages.yml"
echo "  - $REPO_DIR/vars/snap-list.yml"
echo "  - $REPO_DIR/vars/npm-global.yml"
