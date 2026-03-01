#!/usr/bin/env bash
set -euo pipefail

PLAYBOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SEED_DIR="${1:-$PLAYBOOK_DIR/seed}"
RECOVERY_ROOT="${2:-/mnt/recovery}"
USER_NAME="${3:-aziz0220}"
USER_HOME="${4:-/home/$USER_NAME}"

VAR_DIR="$PLAYBOOK_DIR/vars"
SYSTEM_DIR="$SEED_DIR/system"
META_DIR="$SEED_DIR/metadata"
REPO_REMOTE_FILE="$META_DIR/git-remotes.txt"

if [ ! -d "$SEED_DIR" ]; then
  echo "ERROR: seed directory not found: $SEED_DIR" >&2
  exit 1
fi

mkdir -p "$VAR_DIR"

write_yaml_array() {
  local output_file="$1"
  local yaml_key="$2"
  local input_file="$3"
  echo "${yaml_key}:" > "$output_file"
  if [ -f "$input_file" ]; then
    while IFS= read -r item; do
      item="$(echo "$item" | tr -d '\r' | awk '{$1=$1; print}')"
      [ -z "$item" ] && continue
      echo "  - $item" >> "$output_file"
    done < "$input_file"
  fi
}

parse_remote_line() {
  local line="$1"
  if [[ "$line" == \[remote\ * ]]; then
    REPO_REMOTE_NAME="$(awk -F'\"' '{print $2; exit}' <<< "$line")"
    REPO_REMOTE_URL="$(awk -F']: ' '{print $2; exit}' <<< "$line")"
    if [ -n "${REPO_REMOTE_NAME:-}" ] && [ -n "${REPO_REMOTE_URL:-}" ]; then
      return 0
    fi
  fi
  return 1
}

extract_user_from_passwd() {
  local target_file="$1"
  awk -F: -v u="$USER_NAME" '$1==u {print $0; exit}' "$target_file"
}

if [ -f "$META_DIR/user-passwd-line.txt" ]; then
  PASSWD_LINE="$(cat "$META_DIR/user-passwd-line.txt")"
else
  PASSWD_LINE="$(extract_user_from_passwd /etc/passwd)"
fi

if [ -z "${PASSWD_LINE:-}" ] || [[ "$PASSWD_LINE" != *:* ]]; then
  echo "ERROR: could not determine user metadata for $USER_NAME" >&2
  exit 1
fi

USER_UID="$(echo "$PASSWD_LINE" | cut -d: -f3)"
USER_GID="$(echo "$PASSWD_LINE" | cut -d: -f4)"
USER_SHELL="$(echo "$PASSWD_LINE" | cut -d: -f7)"

cat > "$VAR_DIR/user-profile.yml" <<EOF
user_name: ${USER_NAME}
user_uid: ${USER_UID}
user_gid: ${USER_GID}
user_shell: ${USER_SHELL}
EOF

LOCALE_NAME="C.UTF-8"
if [ -f "$SYSTEM_DIR/default_locale" ]; then
  LOCALE_NAME="$(awk -F= '/^LANG=/{print $2; exit}' "$SYSTEM_DIR/default_locale")"
fi
TIMEZONE_NAME=""
if [ -f "$SYSTEM_DIR/timezone" ]; then
  TIMEZONE_NAME="$(tr -d '[:space:]' < "$SYSTEM_DIR/timezone")"
fi
if [ -z "$TIMEZONE_NAME" ]; then
  TIMEZONE_NAME="UTC"
fi

cat > "$VAR_DIR/system-locale.yml" <<EOF
locale_name: ${LOCALE_NAME}
timezone: ${TIMEZONE_NAME}
EOF

{
  echo "seed_groups:"
  shopt -s nullglob
  for group_file in "$META_DIR"/group-*.txt; do
    group_name="$(basename "$group_file" | sed 's/^group-//' | sed 's/\.txt$//')"
    gid="$(awk -F: 'NF >= 3 {print $3; exit}' "$group_file")"
    if [ -n "${gid:-}" ] && [ -n "${group_name:-}" ]; then
      echo "  - {name: ${group_name}, gid: ${gid}}"
    fi
  done
  shopt -u nullglob
} > "$VAR_DIR/groups.yml"

write_yaml_array "$VAR_DIR/installed-packages.yml" "packages" "$META_DIR/installed-packages.txt"
write_yaml_array "$VAR_DIR/systemd-enabled-services.yml" "systemd_services" "$META_DIR/systemd-enabled-services.txt"

if [ -f "$SYSTEM_DIR/etc_apt_sources.list" ]; then
  cp -f "$SYSTEM_DIR/etc_apt_sources.list" "$PLAYBOOK_DIR/roles/system_setup/files/etc_apt_sources.list"
fi
if [ -f "$SYSTEM_DIR/etc_apt_sources_hashicorp.list" ]; then
  cp -f "$SYSTEM_DIR/etc_apt_sources_hashicorp.list" "$PLAYBOOK_DIR/roles/system_setup/files/etc_apt_sources_hashicorp.list"
fi
if [ -f "$SYSTEM_DIR/etc_wsl.conf" ]; then
  cp -f "$SYSTEM_DIR/etc_wsl.conf" "$PLAYBOOK_DIR/roles/system_setup/files/etc_wsl.conf"
fi
if [ -f "$SYSTEM_DIR/hashicorp-archive-keyring.gpg" ]; then
  cp -f "$SYSTEM_DIR/hashicorp-archive-keyring.gpg" "$PLAYBOOK_DIR/roles/system_setup/files/usr_share_keyrings/hashicorp-archive-keyring.gpg"
fi

declare -a required_repos=(
  "cli-agent-orchestrator"
  "pipmedia"
  "SWE-Refactor"
  "RefactorBench"
)

declare -A repo_path
declare -A repo_origin
declare -A repo_upstream
declare -A repo_seen
declare -a repo_order

if [ -f "$REPO_REMOTE_FILE" ]; then
  current_name=""
  current_path=""
  current_origin=""
  current_upstream=""

  flush_repo_entry() {
    if [ -z "$current_name" ]; then
      return
    fi
    if [ -z "${repo_seen[$current_name]+x}" ]; then
      repo_order+=("$current_name")
      repo_seen[$current_name]="1"
    fi
    repo_path["$current_name"]="$current_path"
    repo_origin["$current_name"]="$current_origin"
    repo_upstream["$current_name"]="$current_upstream"
  }

  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == repo:* ]]; then
      flush_repo_entry || true
      raw_path="${line#repo: }"
      raw_path="${raw_path%/}"
      current_name="$(basename "$raw_path")"
      rec_home="${RECOVERY_ROOT}/home/${USER_NAME}"
      if [[ "$raw_path" == "$rec_home/"* ]]; then
        rel="${raw_path#${rec_home}/}"
        current_path="${USER_HOME}/${rel}"
      else
        current_path="${raw_path}"
      fi
      current_origin=""
      current_upstream=""
      continue
    fi
    if [[ "$line" == --- ]]; then
      flush_repo_entry || true
      current_name=""
      current_path=""
      current_origin=""
      current_upstream=""
      continue
    fi
    if parse_remote_line "$line"; then
      remote_name="${REPO_REMOTE_NAME}"
      remote_url="${REPO_REMOTE_URL}"
      if [[ "$remote_name" == "origin" ]]; then
        current_origin="$remote_url"
      elif [[ "$remote_name" == "upstream" ]]; then
        current_upstream="$remote_url"
      fi
    fi
  done < "$REPO_REMOTE_FILE"
  flush_repo_entry || true
fi

ensure_repo() {
  local name="$1"
  local path="$2"
  local origin="$3"
  local upstream="$4"
  if [ -z "${repo_seen[$name]+x}" ]; then
    repo_order+=("$name")
    repo_seen["$name"]="1"
  fi
  repo_path["$name"]="$path"
  repo_origin["$name"]="$origin"
  repo_upstream["$name"]="$upstream"
}

ensure_repo "cli-agent-orchestrator" "$USER_HOME/cli-agent-orchestrator" "https://github.com/aziz0220/cli-agent-orchestrator.git" "https://github.com/awslabs/cli-agent-orchestrator.git"
ensure_repo "pipmedia" "$USER_HOME/pipmedia" "git@github.com:aziz0220/pipmedia.git" ""
ensure_repo "SWE-Refactor" "$USER_HOME/SWE-Refactor/SWE-Refactor" "git@github.com:aziz0220/SWE-Refactor.git" ""
ensure_repo "RefactorBench" "$USER_HOME/RefactorBench" "https://github.com/aziz0220/RefactorBench.git" "https://github.com/microsoft/RefactorBench.git"

cat > "$VAR_DIR/repos.yml" <<'EOF'
repositories:
EOF

escape_yaml() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

for repo in "${required_repos[@]}"; do
  if [ -z "${repo_seen[$repo]+x}" ]; then
    ensure_repo "$repo" "$USER_HOME/$repo" "" ""
  fi
done

for repo in "${repo_order[@]}"; do
  if [ "${repo_path[$repo]:-}" = "" ]; then
    continue
  fi
  yaml_name="$(escape_yaml "$repo")"
  yaml_path="${repo_path[$repo]}"
  if [[ "$yaml_path" == "$USER_HOME/"* ]]; then
    rel_path="${yaml_path#$USER_HOME/}"
    yaml_dest="{{ user_home }}/$rel_path"
  else
    yaml_dest="$(escape_yaml "$yaml_path")"
  fi
  clone_from="${repo_origin[$repo]:-}"
  clone_if_missing="false"
  if [[ "$clone_from" == https://* || "$clone_from" == git@* || "$clone_from" == ssh://* ]]; then
    clone_if_missing="true"
  fi
  {
    echo "  - name: \"$yaml_name\""
    echo "    path: \"$yaml_dest\""
    if [ -n "$clone_from" ] && [[ "$clone_from" == https://* || "$clone_from" == git@* || "$clone_from" == ssh://* ]]; then
      echo "    clone_from: \"$(escape_yaml "$clone_from")\""
    else
      echo "    clone_from: \"\""
    fi
  echo "    clone_if_missing: ${clone_if_missing}"
    if [ -z "${repo_origin[$repo]:-}" ] && [ -z "${repo_upstream[$repo]:-}" ]; then
      echo "    remotes: {}"
    else
      echo "    remotes:"
    fi
    if [ -n "${repo_origin[$repo]:-}" ]; then
      echo "      origin: \"$(escape_yaml "${repo_origin[$repo]}")\""
    fi
    if [ -n "${repo_upstream[$repo]:-}" ]; then
      echo "      upstream: \"$(escape_yaml "${repo_upstream[$repo]}")\""
    fi
  } >> "$VAR_DIR/repos.yml"
  done

echo "Auto-sync complete from seed: $SEED_DIR"
