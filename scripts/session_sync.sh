#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# session_sync.sh — Sync AI coding-agent sessions across machines through an
# encrypted rclone remote (Cloudflare? no — OneDrive, via rclone crypt).
#
# Covers Claude Code (~/.claude) and Codex (~/.codex). Sessions are the agent's
# own append-only JSONL transcripts.
#
# Transport: an rclone `crypt` remote (default `od-crypt:`) wrapped around
# OneDrive. Filenames and contents are encrypted before they leave the machine,
# so the cloud sees only ciphertext.
#
# Policy (deliberately conservative):
#   push  — `rclone copy` this machine's sessions to the remote (add/update,
#           never deletes anything on the remote).
#   pull  — `rclone copy` the remote into the live dirs, moving any replaced
#           local file into ~/.ai-sessions-backups/<timestamp>/ first.
#   status— remote size + last local sync.
#
# Everything within the day window is synced; there is no size cap.
#
# Usage:
#   session_sync.sh push|pull|status
#
# Environment:
#   AI_SESSIONS_REMOTE   rclone remote (default `od-crypt:`)
#   AI_SESSIONS_DAYS     only sync files modified within N days (default 0 = all)
# ---------------------------------------------------------------------------
set -euo pipefail

REMOTE="${AI_SESSIONS_REMOTE:-od-crypt:}"
DAYS="${AI_SESSIONS_DAYS:-0}"

CLAUDE_DIR="$HOME/.claude"
CLAUDE_PROJECTS="$CLAUDE_DIR/projects"
CLAUDE_MEMORY="$CLAUDE_DIR/CLAUDE.md"
CODEX_SESSIONS="$HOME/.codex/sessions"
BACKUP_ROOT="$HOME/.ai-sessions-backups"
STATE_FILE="$HOME/.ai-sessions-state"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { printf "${GREEN}✓${NC} %s\n" "$1"; }
info() { printf "${CYAN}ℹ${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
err()  { printf "${RED}✗${NC} %s\n" "$1" >&2; }

command -v rclone >/dev/null 2>&1 || { err "rclone is not installed (run ./install or ./ansible-run)"; exit 1; }

age_args() {
  [ "$DAYS" -gt 0 ] && printf '%s\n' "--max-age" "${DAYS}d"
}

require_remote() {
  if ! rclone lsd "$REMOTE" >/dev/null 2>&1; then
    err "rclone remote '$REMOTE' is not reachable."
    echo "  Configure it with 'rclone config' (see README: Sync AI sessions)." >&2
    exit 1
  fi
}

stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

cmd_push() {
  require_remote
  if [ -d "$CLAUDE_PROJECTS" ]; then
    # shellcheck disable=SC2046
    rclone copy "$CLAUDE_PROJECTS" "$REMOTE/claude/projects" \
      --create-empty-src-dirs $(age_args)
  fi
  if [ -f "$CLAUDE_MEMORY" ]; then
    rclone copyto "$CLAUDE_MEMORY" "$REMOTE/claude/CLAUDE.md"
  fi
  if [ -d "$CODEX_SESSIONS" ]; then
    # shellcheck disable=SC2046
    rclone copy "$CODEX_SESSIONS" "$REMOTE/codex/sessions" \
      --create-empty-src-dirs $(age_args)
  fi
  printf 'LAST_PUSH=%s\n' "$(stamp)" >> "$STATE_FILE"
  log "Pushed sessions from $(hostname) to $REMOTE"
}

cmd_pull() {
  require_remote
  local ts; ts="$(stamp)"
  local backup_dir="$BACKUP_ROOT/$ts"

  if rclone lsf "$REMOTE/claude/projects" >/dev/null 2>&1; then
    mkdir -p "$CLAUDE_PROJECTS"
    rclone copy "$REMOTE/claude/projects" "$CLAUDE_PROJECTS" \
      --backup-dir="$backup_dir/claude"
    find "$CLAUDE_PROJECTS" -type d -exec chmod 700 {} + 2>/dev/null || true
    find "$CLAUDE_PROJECTS" -type f -exec chmod 600 {} + 2>/dev/null || true
  fi
  if rclone lsf "$REMOTE/claude/CLAUDE.md" >/dev/null 2>&1; then
    mkdir -p "$CLAUDE_DIR"
    rclone copyto "$REMOTE/claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" \
      --backup-dir="$backup_dir/claude"
  fi
  if rclone lsf "$REMOTE/codex/sessions" >/dev/null 2>&1; then
    mkdir -p "$CODEX_SESSIONS"
    rclone copy "$REMOTE/codex/sessions" "$CODEX_SESSIONS" \
      --backup-dir="$backup_dir/codex"
  fi

  printf 'LAST_PULL=%s\n' "$ts" >> "$STATE_FILE"
  log "Pulled sessions into $(hostname)"
  info "Replaced files (if any) were moved to $backup_dir"
  info "Claude Code login does not transfer across machines — run 'claude' then '/login'"
  info "once per machine; afterwards 'claude --continue' will find the synced sessions."
}

cmd_status() {
  echo "remote: $REMOTE"
  echo "window: $([ "$DAYS" -gt 0 ] && echo "last ${DAYS} days" || echo "all sessions")"
  if command -v rclone >/dev/null 2>&1 && rclone lsd "$REMOTE" >/dev/null 2>&1; then
    rclone size "$REMOTE" 2>/dev/null | sed 's/^/remote /'
  else
    warn "remote '$REMOTE' not reachable (is rclone configured?)"
  fi
  if [ -f "$STATE_FILE" ]; then
    echo "local state:"
    sed 's/^/  /' "$STATE_FILE" | tail -4
  fi
}

case "${1:-status}" in
  push)   cmd_push ;;
  pull)   cmd_pull ;;
  status) cmd_status ;;
  *)
    err "unknown command: $1"
    echo "usage: session_sync.sh push|pull|status" >&2
    exit 2
    ;;
esac
