#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${LOG_DIR:-$HOME/codex_pull_logs}"
STATUS_FILE="${STATUS_FILE:-$LOG_DIR/current_status.txt}"
RUN_OUTPUT_LOG="${RUN_OUTPUT_LOG:-$LOG_DIR/latest_run_output.log}"
LATEST_LOG="${LATEST_LOG:-$LOG_DIR/latest.log}"
RUN_ARTIFACT_DIR="${RUN_ARTIFACT_DIR:-$LOG_DIR/artifacts/latest}"
TERMINAL_TITLE="${TERMINAL_TITLE:-Codex server run}"
TAIL_LINES="${TAIL_LINES:-120}"
VIEWER_SCRIPT="$LOG_DIR/live_run_terminal.sh"

mkdir -p "$LOG_DIR"

if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo "[WARN] No graphical display is available; live terminal popup skipped."
  exit 0
fi

cat > "$VIEWER_SCRIPT" <<EOF
#!/usr/bin/env bash
set +e
printf '\\033]0;%s\\007' "$TERMINAL_TITLE"
clear 2>/dev/null || true
cat <<'HEADER'
Codex server run viewer
=======================
This window follows the current server execution.
It stays open so failures remain visible.
Press Ctrl-C to stop following logs, then close the window.
HEADER

echo ""
echo "Status file: $STATUS_FILE"
echo "Diagnostic log: $LATEST_LOG"
echo "Run output:     $RUN_OUTPUT_LOG"
echo "Artifact dir:   $RUN_ARTIFACT_DIR"
echo ""
echo "== Current status =="
if [ -s "$STATUS_FILE" ]; then
  cat "$STATUS_FILE"
else
  echo "No status file yet."
fi

echo ""
echo "== Following logs =="
tail -n "$TAIL_LINES" --retry -F "$LATEST_LOG" "$RUN_OUTPUT_LOG"
echo ""
echo "Log stream ended. Press Enter to close this window."
read -r REPLY
EOF
chmod +x "$VIEWER_SCRIPT"

if [ -n "${TERMINAL_CMD:-}" ]; then
  "$TERMINAL_CMD" -e bash "$VIEWER_SCRIPT" >/dev/null 2>&1 &
  echo "[INFO] live terminal opened with $TERMINAL_CMD"
  exit 0
fi

if command -v x-terminal-emulator >/dev/null 2>&1; then
  x-terminal-emulator -T "$TERMINAL_TITLE" -e bash "$VIEWER_SCRIPT" >/dev/null 2>&1 &
  echo "[INFO] live terminal opened with x-terminal-emulator"
elif command -v gnome-terminal >/dev/null 2>&1; then
  gnome-terminal --title="$TERMINAL_TITLE" -- bash "$VIEWER_SCRIPT" >/dev/null 2>&1 &
  echo "[INFO] live terminal opened with gnome-terminal"
elif command -v xfce4-terminal >/dev/null 2>&1; then
  xfce4-terminal --title="$TERMINAL_TITLE" --command="bash '$VIEWER_SCRIPT'" >/dev/null 2>&1 &
  echo "[INFO] live terminal opened with xfce4-terminal"
elif command -v mate-terminal >/dev/null 2>&1; then
  mate-terminal --title="$TERMINAL_TITLE" -- bash "$VIEWER_SCRIPT" >/dev/null 2>&1 &
  echo "[INFO] live terminal opened with mate-terminal"
elif command -v lxterminal >/dev/null 2>&1; then
  lxterminal --title="$TERMINAL_TITLE" -e bash "$VIEWER_SCRIPT" >/dev/null 2>&1 &
  echo "[INFO] live terminal opened with lxterminal"
elif command -v konsole >/dev/null 2>&1; then
  konsole --new-tab --workdir "$PWD" -p tabtitle="$TERMINAL_TITLE" -e bash "$VIEWER_SCRIPT" >/dev/null 2>&1 &
  echo "[INFO] live terminal opened with konsole"
elif command -v xterm >/dev/null 2>&1; then
  xterm -T "$TERMINAL_TITLE" -e bash "$VIEWER_SCRIPT" >/dev/null 2>&1 &
  echo "[INFO] live terminal opened with xterm"
else
  echo "[WARN] No supported terminal emulator found; live terminal popup skipped."
fi
