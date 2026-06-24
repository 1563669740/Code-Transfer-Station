#!/usr/bin/env bash
set -euo pipefail

# Install Python dependencies with bounded waits and mirror fallback.
#
# Environment overrides:
#   PIP_INDEX_URL       Use one explicit index URL only.
#   PIP_INDEX_URLS      Space-separated fallback index URLs.
#   PIP_INSTALL_TIMEOUT Overall timeout per index attempt, seconds. Default: 300.
#   PIP_NETWORK_TIMEOUT Per network operation timeout passed to pip. Default: 30.
#   PIP_RETRIES         pip retry count per index attempt. Default: 2.

REQUIREMENTS_FILE="${1:-requirements.txt}"
PIP_INSTALL_TIMEOUT="${PIP_INSTALL_TIMEOUT:-300}"
PIP_NETWORK_TIMEOUT="${PIP_NETWORK_TIMEOUT:-30}"
PIP_RETRIES="${PIP_RETRIES:-2}"

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

if [ ! -f "$REQUIREMENTS_FILE" ]; then
  die "requirements file not found: $REQUIREMENTS_FILE"
fi

if ! command -v python >/dev/null 2>&1; then
  die "python not found; activate .venv first or install python3"
fi

if [ -n "${PIP_INDEX_URL:-}" ]; then
  index_urls=("$PIP_INDEX_URL")
elif [ -n "${PIP_INDEX_URLS:-}" ]; then
  # shellcheck disable=SC2206
  index_urls=($PIP_INDEX_URLS)
else
  index_urls=(
    "https://pypi.tuna.tsinghua.edu.cn/simple"
    "https://mirrors.aliyun.com/pypi/simple"
    "https://pypi.org/simple"
  )
fi

has_timeout=0
if command -v timeout >/dev/null 2>&1; then
  has_timeout=1
else
  warn "'timeout' command not found; pip still has per-request timeout but no whole-command timeout"
fi

last_rc=1
for index_url in "${index_urls[@]}"; do
  log "Installing Python dependencies from $REQUIREMENTS_FILE"
  log "pip index=$index_url network_timeout=${PIP_NETWORK_TIMEOUT}s retries=$PIP_RETRIES command_timeout=${PIP_INSTALL_TIMEOUT}s"

  cmd=(
    python -m pip install
    --disable-pip-version-check
    --no-input
    --progress-bar off
    --timeout "$PIP_NETWORK_TIMEOUT"
    --retries "$PIP_RETRIES"
    --index-url "$index_url"
    -r "$REQUIREMENTS_FILE"
  )

  set +e
  if [ "$has_timeout" -eq 1 ] && [ "$PIP_INSTALL_TIMEOUT" -gt 0 ]; then
    timeout --signal=KILL "${PIP_INSTALL_TIMEOUT}s" "${cmd[@]}"
  else
    "${cmd[@]}"
  fi
  last_rc=$?
  set -e

  if [ "$last_rc" -eq 0 ]; then
    log "Python dependencies installed successfully"
    exit 0
  fi

  if [ "$last_rc" -eq 124 ] || [ "$last_rc" -eq 137 ]; then
    warn "pip install timed out for index: $index_url"
  else
    warn "pip install failed for index: $index_url (exit=$last_rc)"
  fi
done

die "pip install failed for all configured indexes"
