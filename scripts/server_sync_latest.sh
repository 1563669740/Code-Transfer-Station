#!/usr/bin/env bash
set -euo pipefail

# One-command control-server sync:
#   1. stop the polling daemon
#   2. fetch and fast-forward to origin/main
#   3. re-run the latest commit once
#   4. restart the polling daemon
#
# By default, local edits to known automation scripts are discarded before merge,
# because those scripts are managed by the repository and may block updates to the
# runner itself. Business-code local edits are never discarded by this script.

PROJECT_DIR="${PROJECT_DIR:-$HOME/codex_projects/project}"
BRANCH="${BRANCH:-main}"
LOG_DIR="${LOG_DIR:-$HOME/codex_pull_logs}"
STATE_DIR="${STATE_DIR:-$HOME/.codex_pull_state}"
FORCE_AUTOMATION_SCRIPTS="${FORCE_AUTOMATION_SCRIPTS:-1}"
RUN_ONCE="${RUN_ONCE:-1}"
RESTART_DAEMON="${RESTART_DAEMON:-1}"
START_DAEMON_LOG="$LOG_DIR/daemon.out"

AUTOMATION_FILES=(
  scripts/server_pull_run.sh
  scripts/server_pull_once.sh
  scripts/server_push_log.sh
  scripts/server_status.sh
  scripts/server_time.sh
  scripts/open_run_terminal.sh
  scripts/install_python_deps.sh
)

usage() {
  cat <<EOF
Usage: bash scripts/server_sync_latest.sh [options]

Options:
  --no-force-scripts   Do not discard local edits to automation scripts.
  --no-run-once        Sync only; do not force-run the latest commit once.
  --no-restart-daemon  Do not restart scripts/server_pull_run.sh after sync.
  -h, --help           Show this help.

Environment overrides:
  PROJECT_DIR, BRANCH, LOG_DIR, STATE_DIR, FORCE_AUTOMATION_SCRIPTS,
  RUN_ONCE, RESTART_DAEMON, plus the normal server runner variables.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-force-scripts)
      FORCE_AUTOMATION_SCRIPTS=0
      shift
      ;;
    --no-run-once)
      RUN_ONCE=0
      shift
      ;;
    --no-restart-daemon)
      RESTART_DAEMON=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

log() {
  echo "[INFO] $*"
}

warn() {
  echo "[WARN] $*" >&2
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

stop_daemon() {
  mkdir -p "$LOG_DIR"

  if [ -f "$LOG_DIR/daemon.pid" ]; then
    pid="$(cat "$LOG_DIR/daemon.pid" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      log "Stopping polling daemon pid=$pid"
      kill "$pid" 2>/dev/null || true
      for _ in 1 2 3 4 5; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
      done
      if kill -0 "$pid" 2>/dev/null; then
        warn "Daemon still alive after graceful stop; sending KILL"
        kill -9 "$pid" 2>/dev/null || true
      fi
    fi
  fi

  pkill -f 'bash scripts/server_pull_run.sh' 2>/dev/null || true
}

checkout_automation_scripts() {
  if [ "$FORCE_AUTOMATION_SCRIPTS" != "1" ]; then
    return 0
  fi

  existing=()
  for file in "${AUTOMATION_FILES[@]}"; do
    if git ls-files --error-unmatch "$file" >/dev/null 2>&1; then
      existing+=("$file")
    fi
  done

  if [ "${#existing[@]}" -eq 0 ]; then
    return 0
  fi

  changed="$(git status --porcelain -- "${AUTOMATION_FILES[@]}" 2>/dev/null || true)"
  if [ -n "$changed" ]; then
    warn "Discarding local edits/untracked files for repository-managed automation scripts:"
    echo "$changed" >&2
    git checkout -- "${existing[@]}"
    git clean -f -- "${AUTOMATION_FILES[@]}" >/dev/null 2>&1 || true
  fi
}

ensure_no_business_conflicts() {
  dirty="$(git status --porcelain -- . ':!scripts/server_pull_run.sh' ':!scripts/server_pull_once.sh' ':!scripts/server_push_log.sh' ':!scripts/server_status.sh' ':!scripts/server_time.sh' ':!scripts/open_run_terminal.sh' ':!scripts/install_python_deps.sh' 2>/dev/null || true)"
  if [ -n "$dirty" ]; then
    echo "$dirty" >&2
    die "Local non-automation changes exist. Commit, stash, or remove them before syncing."
  fi
}

start_daemon() {
  if [ "$RESTART_DAEMON" != "1" ]; then
    log "Skipping daemon restart because RESTART_DAEMON=$RESTART_DAEMON"
    return 0
  fi

  chmod +x scripts/server_pull_run.sh scripts/server_pull_once.sh scripts/server_push_log.sh 2>/dev/null || true
  log "Starting polling daemon"
  nohup bash scripts/server_pull_run.sh > "$START_DAEMON_LOG" 2>&1 &
  echo $! > "$LOG_DIR/daemon.pid"
  log "Polling daemon started: pid=$(cat "$LOG_DIR/daemon.pid")"
  log "Daemon output: $START_DAEMON_LOG"
}

[ -d "$PROJECT_DIR/.git" ] || die "PROJECT_DIR is not a git project: $PROJECT_DIR"
cd "$PROJECT_DIR"

log "Project: $PROJECT_DIR"
log "Branch: $BRANCH"

stop_daemon
checkout_automation_scripts
ensure_no_business_conflicts

log "Fetching origin/$BRANCH"
git fetch origin "$BRANCH"

local_sha="$(git rev-parse HEAD)"
remote_sha="$(git rev-parse "origin/$BRANCH")"
log "local=$local_sha remote=$remote_sha"

if [ "$local_sha" != "$remote_sha" ]; then
  log "Fast-forwarding to origin/$BRANCH"
  git merge --ff-only "origin/$BRANCH"
else
  log "Already at origin/$BRANCH"
fi

if [ "$RUN_ONCE" = "1" ]; then
  log "Forcing latest commit to run once"
  rm -f "$STATE_DIR/last_run_${BRANCH}"
  bash scripts/server_pull_once.sh
else
  log "Skipping one-shot run because RUN_ONCE=$RUN_ONCE"
fi

start_daemon

log "Done. Current status:"
bash scripts/server_status.sh || true
