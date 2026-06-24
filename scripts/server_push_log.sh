#!/usr/bin/env bash
set -euo pipefail

# scripts/server_push_log.sh
#
# 用途：将控制服务器上的运行日志推送到远端日志仓库（或当前仓库的 run-logs 分支）。
#       由 server_pull_run.sh / server_pull_once.sh 在每次执行完成后自动调用。
#
# 环境变量：
#   LOG_PUSH_REMOTE     日志推送目标（Git remote 名或 URL），必填
#   LOG_PUSH_BRANCH     日志推送分支，默认 run-logs
#   LOG_FILE            要推送的日志文件路径，默认 $LOG_DIR/latest.log
#   LOG_REMOTE_NAME     推送到 logs/ 下的文件名；不设置则使用 run_时间戳.log
#   LOG_DIR             日志目录，默认 $HOME/codex_pull_logs
#   PROJECT_DIR         项目目录，默认 $HOME/codex_projects/project
#
# 使用方式：
#   固定文件名回传脚本输出：
#     LOG_PUSH_REMOTE=origin LOG_FILE=$HOME/codex_pull_logs/latest_run_output.log \
#       LOG_REMOTE_NAME=latest_run_output.log bash scripts/server_push_log.sh
#
#   时间戳文件名回传完整日志：
#     LOG_PUSH_REMOTE=origin LOG_FILE=$HOME/codex_pull_logs/latest.log bash scripts/server_push_log.sh
#
# 安全注意：
#   - 如果用同一仓库，代码仓库的 deploy key 需要写权限
#   - 如果用独立日志仓库，日志仓库可以用独立的 deploy key
#   - 日志中不应包含 .env、私钥、token 等敏感信息

LOG_PUSH_REMOTE="${LOG_PUSH_REMOTE:-}"
LOG_PUSH_BRANCH="${LOG_PUSH_BRANCH:-run-logs}"
LOG_FILE="${LOG_FILE:-}"
LOG_REMOTE_NAME="${LOG_REMOTE_NAME:-}"
LOG_DIR="${LOG_DIR:-$HOME/codex_pull_logs}"
PROJECT_DIR="${PROJECT_DIR:-$HOME/codex_projects/project}"

if [ -z "$LOG_FILE" ]; then
  LOG_FILE="$LOG_DIR/latest.log"
fi

if [ -z "$LOG_PUSH_REMOTE" ]; then
  exit 0
fi

if [ ! -f "$LOG_FILE" ]; then
  echo "[WARN] LOG_FILE not found: $LOG_FILE" >&2
  exit 0
fi

cd "$PROJECT_DIR"

SERVER_TIMEZONE="${SERVER_TIMEZONE:-Asia/Shanghai}"
# shellcheck disable=SC1091
. "${PROJECT_DIR:-.}/scripts/server_time.sh"
ts="$(server_log_stamp)"
remote_log_name="${LOG_REMOTE_NAME:-run_${ts}.log}"

# ── 方式 A：推送到同一仓库的分支 ──────────────────────────
if git remote get-url "$LOG_PUSH_REMOTE" >/dev/null 2>&1; then
  TMP_WORKTREE="$(mktemp -d)"
  trap "rm -rf '$TMP_WORKTREE'" EXIT

  git fetch "$LOG_PUSH_REMOTE" "$LOG_PUSH_BRANCH" 2>/dev/null || true

  if git rev-parse --verify "$LOG_PUSH_REMOTE/$LOG_PUSH_BRANCH" >/dev/null 2>&1; then
    git worktree add "$TMP_WORKTREE" "$LOG_PUSH_REMOTE/$LOG_PUSH_BRANCH" --detach
  else
    git worktree add "$TMP_WORKTREE" --detach
    cd "$TMP_WORKTREE"
    git checkout --orphan "$LOG_PUSH_BRANCH"
    git rm -rf . >/dev/null 2>&1 || true
  fi

  cd "$TMP_WORKTREE"

  mkdir -p logs
  cp "$LOG_FILE" "logs/$remote_log_name"

  git add "logs/$remote_log_name"
  GIT_AUTHOR_NAME="codex-pull-runner" \
  GIT_AUTHOR_EMAIL="codex-pull-runner@localhost" \
  GIT_COMMITTER_NAME="codex-pull-runner" \
  GIT_COMMITTER_EMAIL="codex-pull-runner@localhost" \
  git commit -m "run log $ts" || true

  pushed=0
  for i in 1 2 3; do
    if git push "$LOG_PUSH_REMOTE" "HEAD:$LOG_PUSH_BRANCH" 2>/dev/null; then
      echo "[INFO] log pushed to $LOG_PUSH_REMOTE/$LOG_PUSH_BRANCH: $remote_log_name"
      pushed=1
      break
    fi
    sleep $((i * 2))
  done
  if [ "$pushed" -ne 1 ]; then
    echo "[WARN] failed to push log to $LOG_PUSH_REMOTE/$LOG_PUSH_BRANCH after 3 attempts" >&2
  fi

  cd "$PROJECT_DIR"
  git worktree remove "$TMP_WORKTREE" --force 2>/dev/null || rm -rf "$TMP_WORKTREE"
  trap - EXIT

# ── 方式 B：推送到独立的日志仓库 URL ─────────────────────
else
  TMP_DIR="$(mktemp -d)"
  trap "rm -rf '$TMP_DIR'" EXIT

  pushd "$TMP_DIR" >/dev/null
  git init >/dev/null
  if git ls-remote --exit-code --heads "$LOG_PUSH_REMOTE" "$LOG_PUSH_BRANCH" >/dev/null 2>&1; then
    git fetch --depth 1 "$LOG_PUSH_REMOTE" "$LOG_PUSH_BRANCH" >/dev/null
    git checkout -B "$LOG_PUSH_BRANCH" FETCH_HEAD
  else
    git checkout --orphan "$LOG_PUSH_BRANCH"
    git rm -rf . >/dev/null 2>&1 || true
  fi

  mkdir -p logs
  cp "$LOG_FILE" "logs/$remote_log_name"

  git add "logs/$remote_log_name"
  GIT_AUTHOR_NAME="codex-pull-runner" \
  GIT_AUTHOR_EMAIL="codex-pull-runner@localhost" \
  GIT_COMMITTER_NAME="codex-pull-runner" \
  GIT_COMMITTER_EMAIL="codex-pull-runner@localhost" \
  git commit -m "run log $ts" || true

  pushed=0
  for i in 1 2 3; do
    if git push "$LOG_PUSH_REMOTE" "HEAD:$LOG_PUSH_BRANCH" 2>/dev/null; then
      echo "[INFO] log pushed to $LOG_PUSH_REMOTE/$LOG_PUSH_BRANCH: $remote_log_name"
      pushed=1
      break
    fi
    sleep $((i * 2))
  done
  if [ "$pushed" -ne 1 ]; then
    echo "[WARN] failed to push log to $LOG_PUSH_REMOTE/$LOG_PUSH_BRANCH after 3 attempts" >&2
  fi

  popd >/dev/null
  rm -rf "$TMP_DIR"
  trap - EXIT
fi
