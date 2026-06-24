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
# flock -n 防止上一次未完成时再次启动。
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

PROJECT_DIR="${PROJECT_DIR:-$HOME/codex_projects/project}"
BRANCH="${BRANCH:-main}"
LOG_DIR="${LOG_DIR:-$HOME/codex_pull_logs}"
STATE_DIR="${STATE_DIR:-$HOME/.codex_pull_state}"
RUN_TIMEOUT="${RUN_TIMEOUT:-600}"
FETCH_RETRIES="${FETCH_RETRIES:-3}"
FETCH_RETRY_DELAY="${FETCH_RETRY_DELAY:-10}"
LOG_PUSH_REMOTE="${LOG_PUSH_REMOTE:-}"
LOG_PUSH_BRANCH="${LOG_PUSH_BRANCH:-run-logs}"
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

# 检查 timeout 命令是否可用
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

  echo "[INFO] installing dependencies: requirements.txt"
  python -m pip install -r requirements.txt
}

ts="$(date +%Y%m%d_%H%M%S)"
log="$LOG_DIR/${ts}.log"

set +e
(
  set -euo pipefail
  echo "[INFO] time=$ts"
  echo "[INFO] project=$PROJECT_DIR branch=$BRANCH"

  # ── 1. 拉取远端最新引用（带重试） ────────────────────────
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

  # ── 2. 比较 SHA ─────────────────────────────────────────
  local_sha="$(git rev-parse HEAD)"
  remote_sha="$(git rev-parse "origin/$BRANCH")"
  last_run_file="$STATE_DIR/last_run_${BRANCH}"
  last_run_sha="$(cat "$last_run_file" 2>/dev/null || true)"

  echo "[INFO] local=$local_sha remote=$remote_sha last_run=$last_run_sha"

  # ── 3. 已测试过，直接退出 ─────────────────────────────────
  if [ "$remote_sha" = "$last_run_sha" ]; then
    echo "[INFO] remote commit already tested; nothing to do."
    exit 0
  fi

  # ── 4. 有新增，快进合并 ──────────────────────────────────
  if [ "$local_sha" != "$remote_sha" ]; then
    echo "[INFO] new commit detected; pulling with --ff-only."
    if ! git merge --ff-only "origin/$BRANCH" 2>&1; then
      echo "[ERROR] git merge --ff-only failed"
      echo "[HINT] Local changes on server conflict with remote. Manual reset may be needed."
      exit 1
    fi
  fi

  # ── 5. 执行入口（带超时保护） ────────────────────────────
  echo "[INFO] preparing Python environment"
  prepare_python_env

  echo "[INFO] running project entry: bash run.sh"
  if [ "$HAS_TIMEOUT" -eq 1 ] && [ "$RUN_TIMEOUT" -gt 0 ]; then
    timeout --signal=KILL "${RUN_TIMEOUT}s" bash run.sh || {
      rc=$?
      if [ "$rc" -eq 137 ]; then
        echo "[ERROR] bash run.sh timed out after ${RUN_TIMEOUT}s (killed)"
      else
        echo "[ERROR] bash run.sh failed with exit code $rc"
      fi
      exit 1
    }
  else
    bash run.sh
  fi

  # ── 6. 运行测试（带超时保护） ────────────────────────────
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

  # ── 7. 记录已执行 commit ─────────────────────────────────
  git rev-parse HEAD > "$last_run_file"
  echo "[INFO] success commit=$(git rev-parse HEAD)"

) > "$log" 2>&1

exit_code=$?
set -e

# 更新 latest 软链接
ln -sfn "$log" "$LOG_DIR/latest.log"

# ── 8. 可选：推送日志到远端 ────────────────────────────────
if [ -n "$LOG_PUSH_REMOTE" ]; then
  LOG_PUSH_REMOTE="$LOG_PUSH_REMOTE" \
  LOG_PUSH_BRANCH="$LOG_PUSH_BRANCH" \
  LOG_DIR="$LOG_DIR" \
  LOG_FILE="$log" \
  PROJECT_DIR="$PROJECT_DIR" \
  bash "${PROJECT_DIR}/scripts/server_push_log.sh" 2>/dev/null || true
fi

if [ "$exit_code" -eq 0 ]; then
  echo "[INFO] server_pull_once success, log: $log"
else
  echo "[WARN] server_pull_once failed (exit=$exit_code), log: $log" >&2
fi

exit "$exit_code"

