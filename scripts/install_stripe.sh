#!/usr/bin/env bash
set -euo pipefail

case "$(uname -m)" in
  x86_64)
    release_arch=x86_64
    ;;
  aarch64 | arm64)
    release_arch=arm64
    ;;
  *)
    printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

asset_url="$({
  curl -fsSL https://api.github.com/repos/stripe/stripe-cli/releases/latest
} | python3 -c '
import json
import sys

suffix = "linux_" + sys.argv[1] + ".tar.gz"
assets = json.load(sys.stdin)["assets"]
print(next(asset["browser_download_url"] for asset in assets if asset["name"].endswith(suffix)))
' "$release_arch")"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

curl -fsSL "$asset_url" | tar -xz -C "$tmp_dir" stripe
install -m 0755 "$tmp_dir/stripe" /usr/local/bin/stripe