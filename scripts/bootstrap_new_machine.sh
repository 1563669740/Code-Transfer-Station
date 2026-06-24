#!/usr/bin/env bash
set -euo pipefail

# One-time bootstrap for a fresh Linux control machine.
#
# What this script can automate:
#   - install/check git, ssh, python3, pip, and venv support
#   - create a read-only deploy key
#   - configure an SSH host alias for GitHub
#   - clone or fast-forward the project
#   - install Python dependencies in .venv
#   - run bash run.sh and python3 -m pytest -q
#   - start scripts/server_pull_run.sh as a background daemon
#
# What it cannot automate safely:
#   - adding the printed public key to GitHub/Gitee Deploy keys

REPO_SLUG="${REPO_SLUG:-1563669740/Code-Transfer-Station}"
BRANCH="${BRANCH:-main}"
PROJECT_DIR="${PROJECT_DIR:-$HOME/codex_projects/project}"
SSH_ALIAS="${SSH_ALIAS:-github-codex-pull}"
DEPLOY_KEY_PATH="${DEPLOY_KEY_PATH:-$HOME/.ssh/codex_pull_deploy_key}"
LOG_DIR="${LOG_DIR:-$HOME/codex_pull_logs}"
STATE_DIR="${STATE_DIR:-$HOME/.codex_pull_state}"
RUN_TIMEOUT="${RUN_TIMEOUT:-600}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-60}"
START_DAEMON="${START_DAEMON:-1}"
INSTALL_DEPS="${INSTALL_DEPS:-1}"

usage() {
  cat <<EOF
Usage:
  bash scripts/bootstrap_new_machine.sh [options]

Options:
  --repo OWNER/REPO        Repository slug. Default: $REPO_SLUG
  --branch BRANCH         Branch to track. Default: $BRANCH
  --project-dir DIR       Clone directory. Default: $PROJECT_DIR
  --ssh-alias NAME        SSH host alias. Default: $SSH_ALIAS
  --key-path PATH         Deploy key path. Default: $DEPLOY_KEY_PATH
  --no-daemon             Verify only; do not start background polling.
  -h, --help              Show this help.

Environment overrides:
  REPO_SLUG, BRANCH, PROJECT_DIR, SSH_ALIAS, DEPLOY_KEY_PATH, LOG_DIR,
  STATE_DIR, RUN_TIMEOUT, INTERVAL_SECONDS, START_DAEMON, INSTALL_DEPS,
  PIP_INDEX_URL, PIP_INDEX_URLS, PIP_INSTALL_TIMEOUT, PIP_NETWORK_TIMEOUT, PIP_RETRIES
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      REPO_SLUG="${2:?missing value for --repo}"
      shift 2
      ;;
    --branch)
      BRANCH="${2:?missing value for --branch}"
      shift 2
      ;;
    --project-dir)
      PROJECT_DIR="${2:?missing value for --project-dir}"
      shift 2
      ;;
    --ssh-alias)
      SSH_ALIAS="${2:?missing value for --ssh-alias}"
      shift 2
      ;;
    --key-path)
      DEPLOY_KEY_PATH="${2:?missing value for --key-path}"
      shift 2
      ;;
    --no-daemon)
      START_DAEMON=0
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

have() {
  command -v "$1" >/dev/null 2>&1
}

run_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif have sudo; then
    sudo "$@"
  else
    die "sudo is required to install missing packages. Install: $*"
  fi
}

install_apt_packages() {
  if [ "$#" -eq 0 ]; then
    return 0
  fi
  have apt-get || die "apt-get not found. Please install missing packages manually: $*"

  log "Installing missing packages: $*"
  if run_sudo apt-get install -y "$@"; then
    return 0
  fi

  warn "Direct apt install failed. Trying apt-get update once, then retrying."
  run_sudo apt-get update || warn "apt-get update failed; retrying install from existing package cache."
  run_sudo apt-get install -y "$@"
}

ensure_base_tools() {
  local missing=""

  have git || missing="$missing git"
  have ssh || missing="$missing openssh-client"
  have ssh-keygen || missing="$missing openssh-client"
  have ssh-keyscan || missing="$missing openssh-client"
  have python3 || missing="$missing python3"

  # pip/venv are separate packages on many Debian/Ubuntu images.
  # --help is not enough: venv can print help but still fail at runtime
  # because ensurepip is missing.  Test the actual ensurepip import.
  if have python3; then
    python3 -m pip --version >/dev/null 2>&1 || missing="$missing python3-pip"
    python3 -c "import ensurepip" 2>/dev/null || missing="$missing python3-venv"
  else
    missing="$missing python3-pip python3-venv"
  fi

  # shellcheck disable=SC2086
  install_apt_packages $missing
}

create_or_show_deploy_key() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if [ ! -f "$DEPLOY_KEY_PATH" ]; then
    log "Creating deploy key: $DEPLOY_KEY_PATH"
    ssh-keygen -t ed25519 -f "$DEPLOY_KEY_PATH" -C "codex-pull-deploy" -N ""
  else
    log "Using existing deploy key: $DEPLOY_KEY_PATH"
  fi

  [ -f "${DEPLOY_KEY_PATH}.pub" ] || die "Public key not found: ${DEPLOY_KEY_PATH}.pub"

  cat <<EOF

Add this public key as a read-only Deploy key:
  https://github.com/$REPO_SLUG/settings/keys

Title suggestion:
  server-deploy

Public key:
$(cat "${DEPLOY_KEY_PATH}.pub")

Leave "Allow write access" unchecked unless you deliberately need log push-back.
EOF

  if [ -t 0 ]; then
    printf "\nPress Enter after adding the Deploy key in GitHub..."
    read -r _
  else
    warn "Non-interactive shell detected; continuing without waiting for Deploy key confirmation."
  fi
}

configure_ssh() {
  local ssh_config="$HOME/.ssh/config"

  touch "$ssh_config"
  chmod 600 "$ssh_config"

  if grep -qE "^[[:space:]]*Host[[:space:]]+$SSH_ALIAS([[:space:]]|\$)" "$ssh_config"; then
    log "SSH alias already exists in $ssh_config: $SSH_ALIAS"
  else
    log "Adding SSH alias to $ssh_config: $SSH_ALIAS"
    cat >> "$ssh_config" <<EOF

Host $SSH_ALIAS
  HostName github.com
  User git
  IdentityFile $DEPLOY_KEY_PATH
  IdentitiesOnly yes
EOF
  fi

  ssh-keyscan github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
}

verify_ssh_access() {
  local output

  log "Testing GitHub SSH access through alias: $SSH_ALIAS"
  set +e
  output="$(ssh -o BatchMode=yes -o ConnectTimeout=20 -T "git@$SSH_ALIAS" 2>&1)"
  local rc=$?
  set -e

  echo "$output"
  if echo "$output" | grep -qi "successfully authenticated"; then
    return 0
  fi

  die "SSH access failed. Confirm the public key was added to https://github.com/$REPO_SLUG/settings/keys"
}

clone_or_update_repo() {
  local repo_url="git@$SSH_ALIAS:$REPO_SLUG.git"

  mkdir -p "$(dirname "$PROJECT_DIR")"

  if [ -d "$PROJECT_DIR/.git" ]; then
    log "Project already exists; fetching and fast-forwarding: $PROJECT_DIR"
    cd "$PROJECT_DIR"
    git fetch origin "$BRANCH"
    git checkout "$BRANCH"
    git merge --ff-only "origin/$BRANCH"
  else
    log "Cloning $repo_url to $PROJECT_DIR"
    git clone --branch "$BRANCH" "$repo_url" "$PROJECT_DIR"
    cd "$PROJECT_DIR"
  fi
}

prepare_project_python() {
  if [ "$INSTALL_DEPS" != "1" ] || [ ! -f requirements.txt ]; then
    return 0
  fi

  if [ -d .venv ] && [ ! -f .venv/bin/activate ]; then
    warn ".venv exists but is incomplete (missing activate); removing and re-creating"
    rm -rf .venv
  fi

  if [ ! -d .venv ]; then
    log "Creating project virtual environment: .venv"
    python3 -m venv .venv
  fi

  # shellcheck disable=SC1091
  . .venv/bin/activate
  bash scripts/install_python_deps.sh requirements.txt
}

verify_project() {
  log "Running project entry: bash run.sh"
  bash run.sh

  log "Running tests: python3 -m pytest -q"
  python3 -m pytest -q
}

start_daemon() {
  if [ "$START_DAEMON" != "1" ]; then
    log "Skipping daemon start because START_DAEMON=$START_DAEMON"
    return 0
  fi

  chmod +x scripts/server_pull_run.sh scripts/server_pull_once.sh scripts/server_push_log.sh
  mkdir -p "$LOG_DIR" "$STATE_DIR"

  if [ -f "$LOG_DIR/daemon.pid" ]; then
    local old_pid
    old_pid="$(cat "$LOG_DIR/daemon.pid" 2>/dev/null || true)"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      log "Polling daemon is already running: pid=$old_pid"
      return 0
    fi
  fi

  log "Starting polling daemon with log push-back enabled"
  LOG_PUSH_REMOTE=origin \
  PROJECT_DIR="$PROJECT_DIR" \
  BRANCH="$BRANCH" \
  LOG_DIR="$LOG_DIR" \
  STATE_DIR="$STATE_DIR" \
  RUN_TIMEOUT="$RUN_TIMEOUT" \
  INTERVAL_SECONDS="$INTERVAL_SECONDS" \
  nohup bash scripts/server_pull_run.sh > "$LOG_DIR/daemon.out" 2>&1 &
  echo $! > "$LOG_DIR/daemon.pid"
  log "Polling daemon started: pid=$(cat "$LOG_DIR/daemon.pid")"
  log "Latest daemon output: $LOG_DIR/daemon.out"
}

main() {
  log "Bootstrapping control machine for $REPO_SLUG ($BRANCH)"
  ensure_base_tools
  create_or_show_deploy_key
  configure_ssh
  verify_ssh_access
  clone_or_update_repo
  prepare_project_python
  verify_project
  start_daemon

  cat <<EOF

Bootstrap complete.

Project:
  $PROJECT_DIR

Useful checks:
  tail -n 160 "$LOG_DIR/latest.log"
  ps aux | grep server_pull_run | grep -v grep

From now on, update code by pushing commits. The control machine will fetch,
pull, run bash run.sh, and run python3 -m pytest -q automatically.
EOF
}

main "$@"
