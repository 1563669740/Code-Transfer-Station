#!/usr/bin/env bash
set -euo pipefail

# scripts/server_pull_run.sh
#
# 用途：在控制服务器上以守护进程方式运行，定时拉取远端仓库的新提交并自动执行。
# 运行方式（常驻）：
#   nohup bash scripts/server_pull_run.sh > ~/codex_pull_logs/daemon.out 2>&1 &
#
# 环境变量（均可选，有默认值）：
#   PROJECT_DIR        项目目录，默认 $HOME/codex_projects/project
#   BRANCH             要跟踪的分支，默认 main
#   INTERVAL_SECONDS   轮询间隔（秒），默认 30
#   LOG_DIR            日志目录，默认 $HOME/codex_pull_logs
#   STATE_DIR          状态目录（记录上次已执行的 commit），默认 $HOME/.codex_pull_state
#   RUN_TIMEOUT        单次 run.sh 超时（秒），默认 600（10 分钟），设为 0 不限制
#   FETCH_RETRIES      git fetch 失败重试次数，默认 3
#   FETCH_RETRY_DELAY  git fetch 重试间隔（秒），默认 10
#   LOG_PUSH_REMOTE    日志回传远端（Git remote 名或 URL），不设置则不回传
#   LOG_PUSH_BRANCH    日志回传分支，默认 run-logs
#   LOG_PUSH_MODE      run-output 只回传本次 run.sh 输出；full 回传完整诊断日志
#   RUN_OUTPUT_LOG     固定脚本输出文件，默认 $LOG_DIR/latest_run_output.log
#   LOG_RETENTION_DAYS 本机时间戳日志保留天数，默认 14；设为 0 不清理
#   PIP_INDEX_URL      Python 依赖安装镜像源，默认使用国内镜像并回退到官方源
#   PIP_INSTALL_TIMEOUT  pip 安装单个源的整体超时秒数，默认 300
#
# 行为：
#   1. git fetch 检查远端是否有新 commit（失败自动重试）
#   2. 如果远端有新 commit 且该 commit 未被测试过 → git merge --ff-only 拉取
#   3. 执行 bash run.sh（带超时保护），同时把本次 stdout/stderr 写入 latest_run_output.log
#   4. 执行 python3 -m pytest -q（带超时保护）
#   5. 完整诊断日志写入带时间戳的日志文件，latest.log 始终指向最新一次
#   6. 可选：将 latest_run_output.log 以固定文件名推送到远端日志仓库/分支

PROJECT_DIR="${PROJECT_DIR:-$HOME/codex_projects/project}"
BRANCH="${BRANCH:-main}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-30}"
LOG_DIR="${LOG_DIR:-$HOME/codex_pull_logs}"
STATE_DIR="${STATE_DIR:-$HOME/.codex_pull_state}"
RUN_TIMEOUT="${RUN_TIMEOUT:-600}"
FETCH_RETRIES="${FETCH_RETRIES:-3}"
FETCH_RETRY_DELAY="${FETCH_RETRY_DELAY:-10}"
LOG_PUSH_REMOTE="${LOG_PUSH_REMOTE:-}"
LOG_PUSH_BRANCH="${LOG_PUSH_BRANCH:-run-logs}"
LOG_PUSH_MODE="${LOG_PUSH_MODE:-run-output}"
RUN_OUTPUT_LOG="${RUN_OUTPUT_LOG:-$LOG_DIR/latest_run_output.log}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-14}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-.venv}"
INSTALL_DEPS="${INSTALL_DEPS:-1}"

mkdir -p "$LOG_DIR" "$STATE_DIR"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "[ERROR] PROJECT_DIR not found: $PROJECT_DIR" >&2
  echo "[HINT] Clone the repo first:" >&2
  echo "       git clone git@github-codex-pull:OWNER/REPO.git $PROJECT_DIR" >&2
  exit 1
fi

cd "$PROJECT_DIR"

echo "[INFO] server_pull_run started"
echo "[INFO] project=$PROJECT_DIR branch=$BRANCH interval=${INTERVAL_SECONDS}s"
echo "[INFO] log_dir=$LOG_DIR state_dir=$STATE_DIR"
echo "[INFO] run_timeout=${RUN_TIMEOUT}s fetch_retries=$FETCH_RETRIES"
echo "[INFO] log_push_remote=${LOG_PUSH_REMOTE:-disabled}"
echo "[INFO] pid=$$"

if ! command -v timeout >/dev/null 2>&1; then
  echo "[WARN] 'timeout' command not found; run.sh / pytest will have no execution time limit" >&2
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

run_project_entry() {
  echo "[INFO] running project entry: bash run.sh"
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
    echo "[ERROR] bash run.sh timed out after ${RUN_TIMEOUT}s (killed)"
  else
    echo "[ERROR] bash run.sh failed with exit code $rc"
  fi
  exit 1
}

while true; do
  ts="$(date +%Y%m%d_%H%M%S)"
  log="$LOG_DIR/${ts}.log"
  executed_marker="$LOG_DIR/${ts}.executed"
  rm -f "$executed_marker"

  (
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
      echo "[ERROR] git fetch failed after $FETCH_RETRIES attempts"
      exit 1
    fi

    local_sha="$(git rev-parse HEAD)"
    remote_sha="$(git rev-parse "origin/$BRANCH")"
    last_run_file="$STATE_DIR/last_run_${BRANCH}"
    last_run_sha="$(cat "$last_run_file" 2>/dev/null || true)"

    echo "[INFO] local=$local_sha remote=$remote_sha last_run=$last_run_sha"

    if [ "$remote_sha" = "$last_run_sha" ]; then
      echo "[INFO] remote commit already tested; nothing to do."
      exit 0
    fi

    touch "$executed_marker"

    if [ "$local_sha" != "$remote_sha" ]; then
      echo "[INFO] new commit detected; pulling with --ff-only."
      if ! git merge --ff-only "origin/$BRANCH" 2>&1; then
        echo "[ERROR] git merge --ff-only failed"
        echo "[HINT] Local changes may exist on server. Remove the project dir and re-clone if needed."
        exit 1
      fi
    fi

    echo "[INFO] preparing Python environment"
    prepare_python_env

    run_project_entry

    echo "[INFO] running tests: python3 -m pytest -q"
    if [ "$HAS_TIMEOUT" -eq 1 ] && [ "$RUN_TIMEOUT" -gt 0 ]; then
      timeout --signal=KILL "${RUN_TIMEOUT}s" python3 -m pytest -q || {
        rc=$?
        if [ "$rc" -eq 137 ]; then
          echo "[ERROR] pytest timed out after ${RUN_TIMEOUT}s (killed)"
        else
          echo "[ERROR] pytest failed with exit code $rc"
        fi
        exit 1
      }
    else
      python3 -m pytest -q
    fi

    git rev-parse HEAD > "$last_run_file"
    echo "[INFO] success commit=$(git rev-parse HEAD)"

  ) 2>&1 | tee "$log" || true

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

  sleep "$INTERVAL_SECONDS"
done
