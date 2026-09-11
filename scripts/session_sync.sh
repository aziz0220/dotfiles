#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# session_sync.sh — Sync AI coding-agent sessions across machines via a
# private git repository (transport + backup).
#
# Covers Claude Code (~/.claude) and Codex (~/.codex). Sessions are the agent's
# own append-only JSONL transcripts, so git carries them safely.
#
# Policy (deliberately conservative):
#   push  — copies this machine's most recent sessions INTO the repo, prunes the
#           repo to the newest KEEP per project (local copies are never deleted),
#           commits and pushes. Concurrent pushes are retried.
#   pull  — fast-forwards the repo, then copies sessions into the live dirs,
#           backing up (not discarding) any local file it replaces.
#   status— shows sync state and what is configured.
#
# Never synced: credentials/tokens, caches, telemetry.
#
# Usage:
#   session_sync.sh push|pull|status
#
# Environment:
#   AI_SESSIONS_REPO   repo URL   (default https://github.com/aziz0220/ai-sessions.git)
#   AI_SESSIONS_DIR    clone dir  (default ~/.ai-sessions)
#   AI_SESSIONS_KEEP   sessions kept per project in the repo (default 5)
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_URL="${AI_SESSIONS_REPO:-https://github.com/aziz0220/ai-sessions.git}"
CLONE_DIR="${AI_SESSIONS_DIR:-$HOME/.ai-sessions}"
KEEP="${AI_SESSIONS_KEEP:-5}"
# GitHub rejects files over 100 MB and warns over 50 MB. Sessions with huge
# tool output can exceed this; they stay local-only rather than blocking sync.
MAX_MB="${AI_SESSIONS_MAX_MB:-50}"
BRANCH="${AI_SESSIONS_BRANCH:-main}"

CLAUDE_DIR="$HOME/.claude"
CLAUDE_PROJECTS="$CLAUDE_DIR/projects"
CLAUDE_MEMORY="$CLAUDE_DIR/CLAUDE.md"
CODEX_SESSIONS="$HOME/.codex/sessions"
BACKUP_ROOT="$HOME/.ai-sessions-backups"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { printf "${GREEN}✓${NC} %s\n" "$1"; }
info() { printf "${CYAN}ℹ${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
err()  { printf "${RED}✗${NC} %s\n" "$1" >&2; }

command -v git >/dev/null 2>&1 || { err "git is required"; exit 1; }

ensure_clone() {
  if [ -d "$CLONE_DIR/.git" ]; then
    return 0
  fi
  info "Cloning $REPO_URL into $CLONE_DIR"
  mkdir -p "$(dirname "$CLONE_DIR")"
  git clone "$REPO_URL" "$CLONE_DIR"
}

remote_has_branch() {
  git -C "$CLONE_DIR" ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1
}

# Newest KEEP session files of a directory, one path per line.
newest_sessions() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -type f -name '*.jsonl' -size "-${MAX_MB}M" -printf '%T@\t%p\n' 2>/dev/null \
    | sort -rn \
    | head -n "$KEEP" \
    | cut -f2-
}

# Keep only the newest KEEP *.jsonl in a directory (repo side pruning).
prune_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -type f -name '*.jsonl' -printf '%T@\t%p\n' 2>/dev/null \
    | sort -rn \
    | tail -n +"$((KEEP + 1))" \
    | cut -f2- \
    | while IFS= read -r f; do [ -n "$f" ] && rm -f "$f"; done
}

# Remove any session that grew past the size cap so it cannot block a push.
prune_oversized() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  find "$dir" -type f -name '*.jsonl' -size "+${MAX_MB}M" -delete 2>/dev/null || true
}

stage_claude() {
  [ -d "$CLAUDE_PROJECTS" ] || return 0
  local target="$CLONE_DIR/claude/projects"
  mkdir -p "$target"
  for project in "$CLAUDE_PROJECTS"/*/; do
    [ -d "$project" ] || continue
    local slug; slug="$(basename "$project")"
    mkdir -p "$target/$slug"
    while IFS= read -r f; do
      [ -n "$f" ] && [ -f "$f" ] && cp -p "$f" "$target/$slug/"
    done < <(newest_sessions "$project")
    prune_dir "$target/$slug"
    prune_oversized "$target/$slug"
  done
}

stage_claude_memory() {
  [ -f "$CLAUDE_MEMORY" ] || return 0
  mkdir -p "$CLONE_DIR/claude"
  cp -p "$CLAUDE_MEMORY" "$CLONE_DIR/claude/CLAUDE.md"
}

stage_codex() {
  [ -d "$CODEX_SESSIONS" ] || return 0
  mkdir -p "$CLONE_DIR/codex/sessions"
  # Codex nests sessions under date directories; copy the newest KEEP overall.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    local rel="${f#"$CODEX_SESSIONS"/}"
    mkdir -p "$CLONE_DIR/codex/sessions/$(dirname "$rel")"
    cp -p "$f" "$CLONE_DIR/codex/sessions/$rel"
  done < <(find "$CODEX_SESSIONS" -type f -name '*.jsonl' -size "-${MAX_MB}M" -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -n "$KEEP" | cut -f2-)
  prune_oversized "$CLONE_DIR/codex/sessions"
}

cmd_push() {
  ensure_clone
  if remote_has_branch; then
    git -C "$CLONE_DIR" fetch origin "$BRANCH" --quiet || true
    git -C "$CLONE_DIR" checkout "$BRANCH" --quiet 2>/dev/null || true
    git -C "$CLONE_DIR" reset --hard "origin/$BRANCH" --quiet 2>/dev/null || true
  else
    git -C "$CLONE_DIR" checkout -B "$BRANCH" --quiet 2>/dev/null || true
  fi

  stage_claude
  stage_claude_memory
  stage_codex

  git -C "$CLONE_DIR" add -A
  if git -C "$CLONE_DIR" diff --cached --quiet; then
    info "Nothing new to push."
    return 0
  fi
  local count; count="$(git -C "$CLONE_DIR" diff --cached --name-only | wc -l | tr -d ' ')"
  git -C "$CLONE_DIR" -c user.name="dotfiles" -c user.email="dotfiles@localhost" \
    commit --quiet -m "sessions: $(hostname) $(date -u +%Y-%m-%dT%H:%M:%SZ) ($count files)"

  local attempt
  for attempt in 1 2 3; do
    if git -C "$CLONE_DIR" push origin "$BRANCH" 2>/dev/null; then
      log "Pushed $count session file(s) from $(hostname)"
      return 0
    fi
    warn "Push rejected (attempt $attempt/3); re-syncing with remote."
    git -C "$CLONE_DIR" fetch origin "$BRANCH" --quiet || true
    git -C "$CLONE_DIR" pull --no-edit -X ours origin "$BRANCH" --quiet || true
  done
  err "Push failed after 3 attempts. Your local sessions are untouched; retry later."
  exit 1
}

cmd_pull() {
  ensure_clone
  if remote_has_branch; then
    git -C "$CLONE_DIR" fetch origin "$BRANCH"
    git -C "$CLONE_DIR" reset --hard "origin/$BRANCH" --quiet
  else
    warn "Remote branch '$BRANCH' does not exist yet — has anything been pushed?"
    return 0
  fi

  local ts; ts="$(date -u +%Y%m%dT%H%M%SZ)"
  local backup_dir="$BACKUP_ROOT/$ts"
  local changed=0

  if [ -d "$CLONE_DIR/claude/projects" ]; then
    mkdir -p "$CLAUDE_PROJECTS"
    rsync -a --backup --backup-dir="$backup_dir/claude" \
      "$CLONE_DIR/claude/projects/" "$CLAUDE_PROJECTS/"
    changed=1
  fi
  if [ -f "$CLONE_DIR/claude/CLAUDE.md" ]; then
    mkdir -p "$CLAUDE_DIR"
    rsync -a --backup --backup-dir="$backup_dir/claude" \
      "$CLONE_DIR/claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
    changed=1
  fi
  if [ -d "$CLONE_DIR/codex/sessions" ]; then
    mkdir -p "$CODEX_SESSIONS"
    rsync -a --backup --backup-dir="$backup_dir/codex" \
      "$CLONE_DIR/codex/sessions/" "$CODEX_SESSIONS/"
    changed=1
  fi

  if [ "$changed" -eq 1 ]; then
    log "Pulled sessions into $(hostname) (replaced files backed up under $backup_dir)"
  else
    info "Nothing in the repo to pull yet."
  fi
  info "Claude Code login does not transfer across machines — run 'claude' then '/login'"
  info "once per machine; afterwards 'claude --continue' will find the synced sessions."
}

cmd_status() {
  echo "repo:   $REPO_URL"
  echo "clone:  $CLONE_DIR"
  echo "keep:   $KEEP sessions per project"
  echo "max:    ${MAX_MB} MB per session (larger sessions stay local)"
  if [ ! -d "$CLONE_DIR/.git" ]; then
    info "not cloned yet (run: dotfiles sessions push)"
    return 0
  fi
  local behind ahead
  if remote_has_branch; then
    git -C "$CLONE_DIR" fetch origin "$BRANCH" --quiet || true
    behind="$(git -C "$CLONE_DIR" rev-list --count "HEAD..origin/$BRANCH" 2>/dev/null || echo 0)"
    ahead="$(git -C "$CLONE_DIR" rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo 0)"
    echo "sync:   ahead $ahead / behind $behind (branch $BRANCH)"
  fi
  echo "last:   $(git -C "$CLONE_DIR" log -1 --format='%cr by %an' 2>/dev/null || echo none)"
  echo "size:   $(du -sh "$CLONE_DIR" 2>/dev/null | cut -f1)"
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
