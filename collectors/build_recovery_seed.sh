#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RECOVERY_ROOT="${1:-/mnt/recovery}"
TARGET_DIR="${2:-$SCRIPT_DIR/../seed}"
USER_NAME="${3:-aziz0220}"

USER_HOME="$RECOVERY_ROOT/home/$USER_NAME"
PASSWD_FILE="$RECOVERY_ROOT/etc/passwd"
GROUP_FILE="$RECOVERY_ROOT/etc/group"
SEED_HOME_MODE="${SEED_HOME_MODE:-bootstrap}"

if [ ! -d "$USER_HOME" ]; then
  echo "ERROR: user home not found: $USER_HOME" >&2
  exit 1
fi

case "$SEED_HOME_MODE" in
  bootstrap|full) ;;
  *)
    echo "ERROR: invalid SEED_HOME_MODE='$SEED_HOME_MODE' (expected: bootstrap or full)" >&2
    exit 1
    ;;
esac

if [ ! -f "$PASSWD_FILE" ] || [ ! -f "$GROUP_FILE" ]; then
  echo "ERROR: missing passwd/group files under $RECOVERY_ROOT/etc" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR" "$TARGET_DIR/system" "$TARGET_DIR/metadata" "$TARGET_DIR/home"
rm -f "$TARGET_DIR/metadata/group-"*.txt || true
rm -f "$TARGET_DIR/metadata/runtimes-"*.txt || true

cp_if_exists() {
  local src="$1"
  local dst="$2"
  if [ -e "$src" ]; then
    cp -f "$src" "$dst"
  fi
}

extract_installed_packages() {
  local status_file="$1"
  local out_file="$2"
  if [ -f "$status_file" ]; then
    awk '
      /^Package: / {pkg=$2}
      /^Status: install ok installed$/ && pkg != "" {print pkg}
    ' "$status_file" | sort -u > "$out_file"
  else
    : > "$out_file"
  fi
}

extract_enabled_services() {
  local systemd_root="$1"
  local out_file="$2"
  if [ -d "$systemd_root" ]; then
    find "$systemd_root" -type l -printf '%f\n' 2>/dev/null | sort -u > "$out_file"
  else
    : > "$out_file"
  fi
}

extract_user_groups() {
  local passwd_line="$1"
  local group_file="$2"
  local out_dir="$3"
  local user_name="$4"
  local primary_gid
  primary_gid="$(echo "$passwd_line" | cut -d: -f4)"

  while IFS=: read -r grp_name _ grp_gid grp_members; do
    in_membership="false"
    if [ -n "$grp_members" ] && echo ",$grp_members," | grep -q ",$user_name,"; then
      in_membership="true"
    fi
    if [ "$grp_gid" = "$primary_gid" ] || [ "$in_membership" = "true" ]; then
      printf '%s:x:%s:%s\n' "$grp_name" "$grp_gid" "$grp_members" > "$out_dir/group-$grp_name.txt"
    fi
  done < "$group_file"
}

extract_git_remotes() {
  local user_home="$1"
  local out_file="$2"
  : > "$out_file"

  while IFS= read -r git_dir; do
    repo_path="${git_dir%/.git}"
    echo "repo: $repo_path" >> "$out_file"
    if command -v git >/dev/null 2>&1; then
      while IFS= read -r remote_line; do
        remote_name="${remote_line#remote.}"
        remote_name="${remote_name%.url}"
        remote_url="$(git --git-dir="$git_dir" config --get "$remote_line" 2>/dev/null || true)"
        if [ -n "$remote_url" ]; then
          echo "[remote \"$remote_name\"]: $remote_url" >> "$out_file"
        fi
      done < <(git --git-dir="$git_dir" config --name-only --get-regexp '^remote\..*\.url$' 2>/dev/null || true)
    fi
    echo "---" >> "$out_file"
  done < <(find "$user_home" -type d -name .git -prune 2>/dev/null | sort)
}

extract_snap_list() {
  local snaps_dir="$1"
  local out_file="$2"
  if [ -d "$snaps_dir" ]; then
    find "$snaps_dir" -maxdepth 1 -type f -name '*.snap' -printf '%f\n' \
      | sed -E 's/_.*\.snap$//' \
      | sort -u > "$out_file"
  else
    : > "$out_file"
  fi
}

extract_runtime_metadata() {
  local user_home="$1"
  local out_dir="$2"

  if [ -d "$user_home/.nvm/versions/node" ]; then
    find "$user_home/.nvm/versions/node" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
      | sort -u > "$out_dir/runtimes-node.txt"
  else
    : > "$out_dir/runtimes-node.txt"
  fi
  if [ -f "$user_home/.nvm/alias/default" ]; then
    tr -d '[:space:]' < "$user_home/.nvm/alias/default" > "$out_dir/runtimes-node-default.txt"
  else
    : > "$out_dir/runtimes-node-default.txt"
  fi

  for candidate in java maven gradle; do
    candidate_dir="$user_home/.sdkman/candidates/$candidate"
    if [ -d "$candidate_dir" ]; then
      find "$candidate_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
        | grep -v '^current$' \
        | sort -u > "$out_dir/runtimes-sdkman-$candidate.txt" || true
      if [ -L "$candidate_dir/current" ]; then
        basename "$(readlink -f "$candidate_dir/current")" > "$out_dir/runtimes-sdkman-default-$candidate.txt"
      else
        : > "$out_dir/runtimes-sdkman-default-$candidate.txt"
      fi
    else
      : > "$out_dir/runtimes-sdkman-$candidate.txt"
      : > "$out_dir/runtimes-sdkman-default-$candidate.txt"
    fi
  done
}

build_home_manifest() {
  local user_home="$1"
  local manifest_file="$2"
  local tmp_file
  tmp_file="$(mktemp)"

  include_top_level_file() {
    local file_name="$1"
    case "$file_name" in
      .bash_history|.zsh_history|.lesshst|.python_history|.viminfo|.node_repl_history|.motd_shown|.sudo_as_admin_successful|.wget-hsts)
        return 1
        ;;
      .zcompdump|.zcompdump-*.zwc|.zcompdump-*)
        return 1
        ;;
      *)
        return 0
        ;;
    esac
  }

  if [ "$SEED_HOME_MODE" = "full" ]; then
    cat > "$tmp_file" <<'EOF'
.bashrc
.bash_aliases
.bash_logout
.bash_profile
.profile
.zshenv
.zshrc
.tmux.conf
.gitconfig
.ssh
.gnupg
.config
.oh-my-zsh
.claude
.codex
.cursor
.copilot
.docker
.kube
.local
bin
EOF
  else
    cat > "$tmp_file" <<'EOF'
.bashrc
.bash_aliases
.bash_logout
.bash_profile
.profile
.zshenv
.zshrc
.tmux.conf
.gitconfig
.ssh
.gnupg
.config
.oh-my-zsh
.kube
.claude/settings.json
.claude/settings.local.json
.codex/config.toml
.codex/rules
.codex/skills
bin
EOF
  fi

  while IFS= read -r hidden_file; do
    if [ "$SEED_HOME_MODE" = "full" ] || include_top_level_file "$hidden_file"; then
      echo "$hidden_file" >> "$tmp_file"
    fi
  done < <(find "$user_home" -mindepth 1 -maxdepth 1 -name '.*' -type f -printf '%P\n' | sort)

  : > "$manifest_file"
  while IFS= read -r rel_path; do
    [ -z "$rel_path" ] && continue
    if [ -e "$user_home/$rel_path" ]; then
      echo "$rel_path" >> "$manifest_file"
    fi
  done < <(sort -u "$tmp_file")

  rm -f "$tmp_file"
}

copy_home_tree_from_manifest() {
  local user_home="$1"
  local manifest_file="$2"
  local target_home_dir="$3"
  local target_home_parent

  target_home_parent="$(cd "$(dirname "$target_home_dir")" && pwd)"
  target_home_dir="$target_home_parent/$(basename "$target_home_dir")"

  rm -rf "$target_home_dir"
  mkdir -p "$target_home_dir"

  if command -v rsync >/dev/null 2>&1; then
    (
      cd "$user_home"
      # With --files-from, rsync needs explicit recursion to copy directory contents.
      rsync -a --recursive --relative --files-from="$manifest_file" ./ "$target_home_dir"/
    )
  else
    (
      cd "$user_home"
      tar -cf - \
        -T "$manifest_file" \
        --ignore-failed-read
    ) | tar -xf - -C "$target_home_dir"
  fi
}

echo "[*] Writing system metadata snapshots from $RECOVERY_ROOT ..."
cp_if_exists "$RECOVERY_ROOT/etc/timezone" "$TARGET_DIR/system/timezone"
cp_if_exists "$RECOVERY_ROOT/etc/default/locale" "$TARGET_DIR/system/default_locale"
cp_if_exists "$RECOVERY_ROOT/etc/wsl.conf" "$TARGET_DIR/system/etc_wsl.conf"
cp_if_exists "$RECOVERY_ROOT/etc/apt/sources.list" "$TARGET_DIR/system/etc_apt_sources.list"
cp_if_exists "$RECOVERY_ROOT/etc/apt/sources.list.d/hashicorp.list" "$TARGET_DIR/system/etc_apt_sources_hashicorp.list"
cp_if_exists "$RECOVERY_ROOT/usr/share/keyrings/hashicorp-archive-keyring.gpg" "$TARGET_DIR/system/hashicorp-archive-keyring.gpg"

PASSWD_LINE="$(awk -F: -v u="$USER_NAME" '$1==u {print $0; exit}' "$PASSWD_FILE")"
if [ -z "${PASSWD_LINE:-}" ]; then
  echo "ERROR: could not find passwd entry for $USER_NAME in $PASSWD_FILE" >&2
  exit 1
fi
printf '%s\n' "$PASSWD_LINE" > "$TARGET_DIR/metadata/user-passwd-line.txt"

extract_user_groups "$PASSWD_LINE" "$GROUP_FILE" "$TARGET_DIR/metadata" "$USER_NAME"
extract_installed_packages "$RECOVERY_ROOT/var/lib/dpkg/status" "$TARGET_DIR/metadata/installed-packages.txt"
extract_enabled_services "$RECOVERY_ROOT/etc/systemd/system" "$TARGET_DIR/metadata/systemd-enabled-services.txt"
extract_git_remotes "$USER_HOME" "$TARGET_DIR/metadata/git-remotes.txt"
extract_snap_list "$RECOVERY_ROOT/var/lib/snapd/snaps" "$TARGET_DIR/metadata/snap-list.txt"
extract_runtime_metadata "$USER_HOME" "$TARGET_DIR/metadata"

MANIFEST_FILE="$(cd "$TARGET_DIR/metadata" && pwd)/home-manifest.txt"
build_home_manifest "$USER_HOME" "$MANIFEST_FILE"

echo "[*] Building home tree snapshot in $TARGET_DIR/home ..."
copy_home_tree_from_manifest "$USER_HOME" "$MANIFEST_FILE" "$TARGET_DIR/home"

rm -f "$TARGET_DIR/home-config.tar.gz" "$TARGET_DIR/home-config.tar.gz.aes256"

echo "[+] Seed complete: $TARGET_DIR"
