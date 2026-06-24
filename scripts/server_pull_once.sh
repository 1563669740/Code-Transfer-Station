#!/usr/bin/env bash
set -euo pipefail

# scripts/server_pull_once.sh
#
# 用途：在控制服务器上单次执行，检查远端是否有新 commit 并运行。
#       配合 cron 使用，每分钟触发一次。
#
# cron 配置示例：
#   crontab -e
#   * * * * * flock -n /tmp/codex_pull.lock bash $HOME/codex_projects/project/scripts/server_pull_once.sh
#
# 环境变量（均可选，有默认值）：
#   PROJECT_DIR        项目目录，默认 $HOME/codex_projects/project
#   BRANCH             要跟踪的分支，默认 main
#   LOG_DIR            日志目录，默认 $HOME/codex_pull_logs
#   STATE_DIR          状态目录（记录上次已执行的 commit），默认 $HOME/.codex_pull_state
#   RUN_TIMEOUT        单次 run.sh 超时（秒），默认 600（10 分钟），设为 0 不限制
#   FETCH_RETRIES      git fetch 失败重试次数，默认 3
#   FETCH_RETRY_DELAY  git fetch 重试间隔（秒），默认 10
#   LOG_PUSH_REMOTE    日志回传远端（Git remote 名或 URL），不设置则不回传
#   LOG_PUSH_BRANCH    日志回传分支，默认 run-logs
#   LOG_PUSH_MODE      run-output 只回传本次 run.sh 输出；full 回传完整诊断日志
#   RUN_OUTPUT_LOG     固定脚本输出文件，默认 $LOG_DIR/latest_run_output.log
#   ARTIFACT_ROOT      运行产物根目录，默认 $LOG_DIR/artifacts
#   RUN_ARTIFACT_DIR   固定的本次产物目录，默认 $ARTIFACT_ROOT/latest
#   ARTIFACT_ARCHIVE_DIR 旧产物归档目录，默认 $ARTIFACT_ROOT/archive
#   LOG_RETENTION_DAYS 本机时间戳日志保留天数，默认 14；设为 0 不清理
#   PIP_INDEX_URL      Python 依赖安装镜像源，默认使用国内镜像并回退到官方源
#   PIP_INSTALL_TIMEOUT  pip 安装单个源的整体超时秒数，默认 300

PROJECT_DIR="${PROJECT_DIR:-$HOME/codex_projects/project}"
BRANCH="${BRANCH:-main}"
LOG_DIR="${LOG_DIR:-$HOME/codex_pull_logs}"
STATE_DIR="${STATE_DIR:-$HOME/.codex_pull_state}"
RUN_TIMEOUT="${RUN_TIMEOUT:-600}"
FETCH_RETRIES="${FETCH_RETRIES:-3}"
FETCH_RETRY_DELAY="${FETCH_RETRY_DELAY:-10}"
LOG_PUSH_REMOTE="${LOG_PUSH_REMOTE:-}"
LOG_PUSH_BRANCH="${LOG_PUSH_BRANCH:-run-logs}"
LOG_PUSH_MODE="${LOG_PUSH_MODE:-run-output}"
RUN_OUTPUT_LOG="${RUN_OUTPUT_LOG:-$LOG_DIR/latest_run_output.log}"
STATUS_FILE="${STATUS_FILE:-$LOG_DIR/current_status.txt}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-$LOG_DIR/artifacts}"
RUN_ARTIFACT_DIR="${RUN_ARTIFACT_DIR:-$ARTIFACT_ROOT/latest}"
ARTIFACT_ARCHIVE_DIR="${ARTIFACT_ARCHIVE_DIR:-$ARTIFACT_ROOT/archive}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-14}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-.venv}"
INSTALL_DEPS="${INSTALL_DEPS:-1}"

mkdir -p "$LOG_DIR" "$STATE_DIR" "$ARTIFACT_ROOT" "$ARTIFACT_ARCHIVE_DIR"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "[ERROR] PROJECT_DIR not found: $PROJECT_DIR" >&2
  echo "[HINT] Clone the repo first:" >&2
  echo "       git clone git@github-codex-pull:OWNER/REPO.git $PROJECT_DIR" >&2
  exit 1
fi

cd "$PROJECT_DIR"

write_status() {
  stage="$1"
  shift || true
  message="$*"
  status_time="$(date '+%Y-%m-%d %H:%M:%S %z')"
  current_commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  {
    echo "time=$status_time"
    echo "stage=$stage"
    echo "commit=$current_commit"
    echo "message=$message"
    echo "latest_log=$LOG_DIR/latest.log"
    echo "run_output=$RUN_OUTPUT_LOG"
    echo "artifact_dir=$RUN_ARTIFACT_DIR"
  } > "$STATUS_FILE"
  echo "[STATUS] $stage - $message"
}

write_status "started" "single run project=$PROJECT_DIR branch=$BRANCH"

if ! command -v timeout >/dev/null 2>&1; then
  HAS_TIMEOUT=0
else
  HAS_TIMEOUT=1
fi

activate_python_env() {
  if [ -f "$VENV_DIR/bin/activate" ]; then
    # shellcheck disable=SC1091
    . "$VENV_DIR/bin/activate"
  elif [ -f "$VENV_DIR/Scripts/activate" ]; then
    # shellcheck disable=SC1091
    . "$VENV_DIR/Scripts/activate"
  fi
}

prepare_python_env() {
  activate_python_env

  if [ "$INSTALL_DEPS" != "1" ] || [ ! -f "requirements.txt" ]; then
    return 0
  fi

  if [ ! -f "$VENV_DIR/bin/activate" ] && [ ! -f "$VENV_DIR/Scripts/activate" ]; then
    echo "[INFO] creating virtual environment: $VENV_DIR"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
    activate_python_env
  fi

  bash scripts/install_python_deps.sh requirements.txt
}

cleanup_local_logs() {
  if [ "$LOG_RETENTION_DAYS" -gt 0 ] 2>/dev/null; then
    find "$LOG_DIR" -maxdepth 1 -type f -mtime +"$LOG_RETENTION_DAYS" \
      \( -name '*.log' -o -name '*.executed' \) \
      ! -name 'latest_run_output.log' -delete 2>/dev/null || true
  fi
}

prepare_run_artifact_dir() {
  run_ts="$1"
  export RUN_ARTIFACT_TIME="$(date '+%Y-%m-%d %H:%M:%S %z')"

  if [ -e "$RUN_ARTIFACT_DIR" ] || [ -L "$RUN_ARTIFACT_DIR" ]; then
    archive_path="$ARTIFACT_ARCHIVE_DIR/${run_ts}_$(git rev-parse --short HEAD)"
    mv "$RUN_ARTIFACT_DIR" "$archive_path"
    echo "[INFO] previous artifacts archived: $archive_path"
  fi

  mkdir -p "$RUN_ARTIFACT_DIR"
}

append_artifact_summary() {
  {
    echo ""
    echo "[INFO] artifact_dir=$RUN_ARTIFACT_DIR"
    echo "[INFO] artifact_summary_time=$(date '+%Y-%m-%d %H:%M:%S %z')"

    artifact_count="$(find "$RUN_ARTIFACT_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${artifact_count:-0}" -eq 0 ] 2>/dev/null; then
      echo "[INFO] artifacts: none"
      return 0
    fi

    echo "[INFO] artifacts:"
    find "$RUN_ARTIFACT_DIR" -type f -printf '[INFO] artifact %TY-%Tm-%Td %TH:%TM:%TS %TZ | %s bytes | %P\n' 2>/dev/null | sort
  } | tee -a "$RUN_OUTPUT_LOG"
}
run_project_entry() {
  write_status "running" "bash run.sh"
  echo "[INFO] running project entry: bash run.sh"
  echo "[INFO] run_artifact_dir=$RUN_ARTIFACT_DIR"
  echo "[INFO] run_artifact_time=$RUN_ARTIFACT_TIME"
  : > "$RUN_OUTPUT_LOG"

  set +e
  if [ "$HAS_TIMEOUT" -eq 1 ] && [ "$RUN_TIMEOUT" -gt 0 ]; then
    timeout --signal=KILL "${RUN_TIMEOUT}s" bash run.sh 2>&1 | tee "$RUN_OUTPUT_LOG"
    rc=${PIPESTATUS[0]}
  else
    bash run.sh 2>&1 | tee "$RUN_OUTPUT_LOG"
    rc=${PIPESTATUS[0]}
  fi
  set -e

  if [ "$rc" -eq 0 ]; then
    return 0
  elif [ "$rc" -eq 137 ]; then
    write_status "failed" "bash run.sh timed out after ${RUN_TIMEOUT}s"
    echo "[ERROR] bash run.sh timed out after ${RUN_TIMEOUT}s (killed)"
  else
    write_status "failed" "bash run.sh failed with exit code $rc"
    echo "[ERROR] bash run.sh failed with exit code $rc"
  fi
  exit 1
}

ts="$(date +%Y%m%d_%H%M%S)"
log="$LOG_DIR/${ts}.log"
executed_marker="$LOG_DIR/${ts}.executed"
rm -f "$executed_marker"

set +e
(
  set -euo pipefail
  trap 'rc=$?; if [ "$rc" -ne 0 ]; then write_status "failed" "script failed with exit code $rc; see $LOG_DIR/latest.log"; fi' EXIT
  ln -sfn "$log" "$LOG_DIR/latest.log"
  write_status "fetching" "checking origin/$BRANCH"
  echo "[INFO] time=$ts"
  echo "[INFO] project=$PROJECT_DIR branch=$BRANCH"

  fetch_ok=0
  for i in $(seq 1 "$FETCH_RETRIES"); do
    if git fetch origin "$BRANCH" 2>&1; then
      fetch_ok=1
      break
    fi
    echo "[WARN] git fetch failed (attempt $i/$FETCH_RETRIES), retrying in ${FETCH_RETRY_DELAY}s..."
    sleep "$FETCH_RETRY_DELAY"
  done
  if [ "$fetch_ok" -eq 0 ]; then
    write_status "failed" "git fetch failed after $FETCH_RETRIES attempts"
    echo "[ERROR] git fetch failed after $FETCH_RETRIES attempts"
    exit 1
  fi

  local_sha="$(git rev-parse HEAD)"
  remote_sha="$(git rev-parse "origin/$BRANCH")"
  last_run_file="$STATE_DIR/last_run_${BRANCH}"
  last_run_sha="$(cat "$last_run_file" 2>/dev/null || true)"

  write_status "comparing" "local=${local_sha:0:7} remote=${remote_sha:0:7} last_run=${last_run_sha:0:7}"
  echo "[INFO] local=$local_sha remote=$remote_sha last_run=$last_run_sha"

  if [ "$remote_sha" = "$last_run_sha" ]; then
    write_status "idle" "remote commit already tested: ${remote_sha:0:7}"
    echo "[INFO] remote commit already tested; nothing to do."
    exit 0
  fi

  touch "$executed_marker"

  if [ "$local_sha" != "$remote_sha" ]; then
    write_status "pulling" "merging origin/$BRANCH ${remote_sha:0:7}"
    echo "[INFO] new commit detected; pulling with --ff-only."
    if ! git merge --ff-only "origin/$BRANCH" 2>&1; then
      write_status "failed" "git merge --ff-only failed"
      echo "[ERROR] git merge --ff-only failed"
      echo "[HINT] Local changes on server conflict with remote. Manual reset may be needed."
      exit 1
    fi
  fi

  write_status "installing-deps" "preparing Python environment"
  echo "[INFO] preparing Python environment"
  prepare_python_env

  prepare_run_artifact_dir "$ts"

  run_project_entry
  append_artifact_summary

  write_status "testing" "python3 -m pytest -q"
  echo "[INFO] running tests: python3 -m pytest -q"
  if [ "$HAS_TIMEOUT" -eq 1 ] && [ "$RUN_TIMEOUT" -gt 0 ]; then
    timeout --signal=KILL "${RUN_TIMEOUT}s" python3 -m pytest -q || {
      rc=$?
      if [ "$rc" -eq 137 ]; then
        write_status "failed" "pytest timed out after ${RUN_TIMEOUT}s"
        echo "[ERROR] pytest timed out after ${RUN_TIMEOUT}s (killed)"
      else
        write_status "failed" "pytest failed with exit code $rc"
        echo "[ERROR] pytest failed with exit code $rc"
      fi
      exit 1
    }
  else
    python3 -m pytest -q
  fi

  git rev-parse HEAD > "$last_run_file"
  write_status "success" "commit=$(git rev-parse --short HEAD)"
  echo "[INFO] success commit=$(git rev-parse HEAD)"

) 2>&1 | tee "$log"

exit_code=$?
set -e

ln -sfn "$log" "$LOG_DIR/latest.log"

if [ -f "$executed_marker" ] && [ -n "$LOG_PUSH_REMOTE" ]; then
  push_log_file="$log"
  push_remote_name=""
  if [ "$LOG_PUSH_MODE" = "run-output" ] && [ -f "$RUN_OUTPUT_LOG" ]; then
    push_log_file="$RUN_OUTPUT_LOG"
    push_remote_name="latest_run_output.log"
  fi

  echo "[INFO] pushing execution log to ${LOG_PUSH_REMOTE}/${LOG_PUSH_BRANCH}" | tee -a "$log"
  LOG_PUSH_REMOTE="$LOG_PUSH_REMOTE" \
  LOG_PUSH_BRANCH="$LOG_PUSH_BRANCH" \
  LOG_DIR="$LOG_DIR" \
  LOG_FILE="$push_log_file" \
  LOG_REMOTE_NAME="$push_remote_name" \
  PROJECT_DIR="$PROJECT_DIR" \
  bash "${PROJECT_DIR}/scripts/server_push_log.sh" 2>&1 | tee -a "$log" || true
fi
rm -f "$executed_marker"
cleanup_local_logs

if [ "$exit_code" -eq 0 ]; then
  echo "[INFO] server_pull_once success, log: $log"
else
  echo "[WARN] server_pull_once failed (exit=$exit_code), log: $log" >&2
fi

exit "$exit_code"
