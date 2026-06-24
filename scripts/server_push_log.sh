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
#   LOG_DIR             日志目录，默认 $HOME/codex_pull_logs
#   PROJECT_DIR         项目目录，默认 $HOME/codex_projects/project
#
# 使用方式：
#   方式 A：推送到同一仓库的 run-logs 分支（推荐，无需额外仓库）
#     LOG_PUSH_REMOTE=origin bash scripts/server_push_log.sh
#
#   方式 B：推送到独立的日志仓库（需要额外配置 deploy key 和 remote）
#     git remote add log-repo git@github-log:OWNER/project-run-logs.git
#     LOG_PUSH_REMOTE=log-repo bash scripts/server_push_log.sh
#
# 安全注意：
#   - 如果用方式 A，代码仓库的 deploy key 需要写权限
#   - 如果用方式 B，日志仓库可以用独立的 deploy key
#   - 无论哪种方式，日志中不应包含 .env、私钥、token 等敏感信息

LOG_PUSH_REMOTE="${LOG_PUSH_REMOTE:-}"
LOG_PUSH_BRANCH="${LOG_PUSH_BRANCH:-run-logs}"
LOG_FILE="${LOG_FILE:-}"
LOG_DIR="${LOG_DIR:-$HOME/codex_pull_logs}"
PROJECT_DIR="${PROJECT_DIR:-$HOME/codex_projects/project}"

# 如果未指定 LOG_FILE，使用 latest.log
if [ -z "$LOG_FILE" ]; then
  LOG_FILE="$LOG_DIR/latest.log"
fi

# 如果未配置 LOG_PUSH_REMOTE，静默退出（日志回传是可选的）
if [ -z "$LOG_PUSH_REMOTE" ]; then
  exit 0
fi

if [ ! -f "$LOG_FILE" ]; then
  echo "[WARN] LOG_FILE not found: $LOG_FILE" >&2
  exit 0
fi

cd "$PROJECT_DIR"

ts="$(date +%Y%m%d_%H%M%S)"
remote_log_name="run_${ts}.log"

# ── 方式 A：推送到同一仓库的分支 ──────────────────────────
# 判断 LOG_PUSH_REMOTE 是否是已知的 git remote（如 origin）
if git remote get-url "$LOG_PUSH_REMOTE" >/dev/null 2>&1; then
  # 同一个仓库：用独立分支存储日志（run-logs），不会污染主分支历史
  TMP_WORKTREE="$(mktemp -d)"
  trap "rm -rf '$TMP_WORKTREE'" EXIT

  # 创建孤立分支（如果还不存在），确保日志历史独立
  git fetch "$LOG_PUSH_REMOTE" "$LOG_PUSH_BRANCH" 2>/dev/null || true

  if git rev-parse --verify "$LOG_PUSH_REMOTE/$LOG_PUSH_BRANCH" >/dev/null 2>&1; then
    # 分支已存在：在其基础上添加新日志
    git worktree add "$TMP_WORKTREE" "$LOG_PUSH_REMOTE/$LOG_PUSH_BRANCH" --detach
  else
    # 分支不存在：创建孤立 worktree
    git worktree add "$TMP_WORKTREE" --detach
    cd "$TMP_WORKTREE"
    git checkout --orphan "$LOG_PUSH_BRANCH"
  fi

  cd "$TMP_WORKTREE"

  # 拷贝日志到 worktree
  mkdir -p logs
  cp "$LOG_FILE" "logs/$remote_log_name"

  # 提交并推送
  git add "logs/$remote_log_name"
  git commit -m "run log $ts" || true  # 如果内容未变，跳过

  # 推送到远端 run-logs 分支（最多重试 3 次）
  for i in 1 2 3; do
    if git push "$LOG_PUSH_REMOTE" "HEAD:$LOG_PUSH_BRANCH" 2>/dev/null; then
      echo "[INFO] log pushed to $LOG_PUSH_REMOTE/$LOG_PUSH_BRANCH: $remote_log_name"
      break
    fi
    sleep $((i * 2))
  done

  # 清理 worktree
  cd "$PROJECT_DIR"
  git worktree remove "$TMP_WORKTREE" --force 2>/dev/null || rm -rf "$TMP_WORKTREE"
  trap - EXIT

# ── 方式 B：推送到独立的日志仓库 URL ─────────────────────
else
  TMP_DIR="$(mktemp -d)"
  trap "rm -rf '$TMP_DIR'" EXIT

  pushd "$TMP_DIR" >/dev/null
  git clone --depth 1 "$LOG_PUSH_REMOTE" . 2>/dev/null || git init
  git checkout -B "$LOG_PUSH_BRANCH" 2>/dev/null || git checkout --orphan "$LOG_PUSH_BRANCH"

  mkdir -p logs
  cp "$LOG_FILE" "logs/$remote_log_name"

  git add "logs/$remote_log_name"
  git commit -m "run log $ts" || true

  for i in 1 2 3; do
    if git push "$LOG_PUSH_REMOTE" "HEAD:$LOG_PUSH_BRANCH" 2>/dev/null; then
      echo "[INFO] log pushed to LOG_PUSH_REMOTE/$LOG_PUSH_BRANCH: $remote_log_name"
      break
    fi
    sleep $((i * 2))
  done

  popd >/dev/null
  rm -rf "$TMP_DIR"
  trap - EXIT
fi
