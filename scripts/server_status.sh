#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${LOG_DIR:-$HOME/codex_pull_logs}"
STATUS_FILE="${STATUS_FILE:-$LOG_DIR/current_status.txt}"
RUN_OUTPUT_LOG="${RUN_OUTPUT_LOG:-$LOG_DIR/latest_run_output.log}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-$LOG_DIR/artifacts}"
TAIL_LINES="${TAIL_LINES:-80}"
FOLLOW=0

case "${1:-}" in
  -f|--follow)
    FOLLOW=1
    ;;
  -h|--help)
    cat <<EOF
Usage: bash scripts/server_status.sh [--follow]

Shows the control-server pull runner status, recent logs, and latest artifacts.
Environment overrides: LOG_DIR, STATUS_FILE, RUN_OUTPUT_LOG, ARTIFACT_ROOT, TAIL_LINES.
EOF
    exit 0
    ;;
  "")
    ;;
  *)
    echo "[ERROR] unknown option: $1" >&2
    exit 2
    ;;
esac

section() {
  echo ""
  echo "== $1 =="
}

show_file_or_empty() {
  path="$1"
  empty_message="$2"
  if [ -s "$path" ]; then
    cat "$path"
  else
    echo "$empty_message"
  fi
}

show_once() {
  section "Current status"
  show_file_or_empty "$STATUS_FILE" "No status file yet: $STATUS_FILE"

  section "Daemon process"
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -af 'server_pull_run.sh' || echo "server_pull_run.sh is not running"
  else
    ps aux | grep 'server_pull_run.sh' | grep -v grep || echo "server_pull_run.sh is not running"
  fi

  section "Latest artifacts"
  latest_artifact_dir="$ARTIFACT_ROOT/latest"
  if [ -d "$latest_artifact_dir" ]; then
    find "$latest_artifact_dir" -maxdepth 1 -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS %TZ | %s bytes | %f\n' 2>/dev/null | sort || true
    artifact_count="$(find "$latest_artifact_dir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${artifact_count:-0}" -eq 0 ] 2>/dev/null; then
      echo "No files in $latest_artifact_dir"
    fi
  else
    echo "No artifact directory yet: $latest_artifact_dir"
  fi

  section "Recent run output"
  if [ -s "$RUN_OUTPUT_LOG" ]; then
    tail -n "$TAIL_LINES" "$RUN_OUTPUT_LOG"
  else
    echo "No run output yet: $RUN_OUTPUT_LOG"
  fi

  section "Recent diagnostic log"
  if [ -e "$LOG_DIR/latest.log" ]; then
    tail -n "$TAIL_LINES" "$LOG_DIR/latest.log"
  else
    echo "No latest log yet: $LOG_DIR/latest.log"
  fi
}

show_once

if [ "$FOLLOW" -eq 1 ]; then
  section "Following logs"
  echo "Press Ctrl-C to stop."
  tail -n "$TAIL_LINES" --retry -F "$LOG_DIR/latest.log" "$RUN_OUTPUT_LOG"
else
  echo ""
  echo "Tip: bash scripts/server_status.sh --follow"
fi
