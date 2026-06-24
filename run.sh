#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ -f ".venv/bin/activate" ]; then
  source ".venv/bin/activate"
elif [ -f ".venv/Scripts/activate" ]; then
  source ".venv/Scripts/activate"
fi

# 优先使用 python，其次 python3
if command -v python >/dev/null 2>&1; then
  python main.py "$@"
elif command -v python3 >/dev/null 2>&1; then
  python3 main.py "$@"
else
  echo "[ERROR] Python not found" >&2
  exit 1
fi