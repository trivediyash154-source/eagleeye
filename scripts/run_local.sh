#!/usr/bin/env bash
# EAGLE EYE — one-command local run (Linux / macOS):  API + web console on http://localhost:8000
#
#   ./scripts/run_local.sh               first run: creates .venv, installs deps, downloads model weights
#   ./scripts/run_local.sh --rebuild     also rebuilds the Flutter web console (needs Flutter 3.47+)
#   PORT=8080 ./scripts/run_local.sh     different port
#
# Requirements: Python 3.11–3.13 (3.11 recommended), curl, unzip, ~6 GB free disk (PyTorch).
# Supported: Linux x86_64/arm64, macOS 14+ on Apple Silicon. Windows: scripts\run_local.ps1.
# Flutter is NOT required: a prebuilt web console is committed in frontend/prebuilt/web.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-8000}"
VENV="${EAGLEEYE_VENV:-$ROOT/.venv}"

say() { printf '\033[1;36m[eagle-eye]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[eagle-eye] %s\033[0m\n' "$*" >&2; exit 1; }

pick_python() {
  if [ -n "${PYTHON:-}" ]; then echo "$PYTHON"; return; fi
  for c in python3.11 python3.12 python3.13 python3; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if (3,11) <= sys.version_info[:2] <= (3,13) else 1)' 2>/dev/null; then
      echo "$c"; return
    fi
  done
  die "Python 3.11–3.13 not found (3.11 recommended). Install it or set PYTHON=/path/to/python."
}

command -v curl >/dev/null || die "curl is required"
command -v unzip >/dev/null || die "unzip is required"

# 1. Python environment (reinstalled automatically when requirements.txt changes)
if [ ! -x "$VENV/bin/python" ]; then
  PY="$(pick_python)"
  say "Creating virtual environment with $PY ($("$PY" --version 2>&1))"
  "$PY" -m venv "$VENV"
fi
REQ="$ROOT/backend/requirements.txt"
STAMP="$VENV/.eagleeye-requirements"
CUR="$("$VENV/bin/python" -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$REQ")"
if [ ! -f "$STAMP" ] || [ "$(cat "$STAMP")" != "$CUR" ]; then
  say "Installing Python dependencies (first run downloads PyTorch, ~2–3 GB; this can take several minutes)"
  "$VENV/bin/python" -m pip install --upgrade pip >/dev/null
  "$VENV/bin/python" -m pip install -r "$REQ"
  echo "$CUR" > "$STAMP"
fi

# 2. Model weights not stored in git (YOLOv8n COCO, EasyOCR)
"$ROOT/scripts/setup_models.sh"

# 3. Demo fixtures are committed; regenerate only if missing
if [ ! -f "$ROOT/data/demo/fixtures.json" ]; then
  say "Generating demonstration fixtures"
  (cd "$ROOT/backend" && "$VENV/bin/python" scripts/generate_demo_fixtures.py)
fi

# 4. Web console: local build if requested/available, else the committed prebuilt bundle
if [ "${1:-}" = "--rebuild" ]; then
  command -v flutter >/dev/null || die "--rebuild needs the Flutter SDK (3.47+) on PATH"
  "$ROOT/scripts/build_web.sh"
fi
if [ ! -f "$ROOT/frontend/build/web/index.html" ] && [ ! -f "$ROOT/frontend/prebuilt/web/index.html" ]; then
  die "No web console build found (frontend/prebuilt/web is missing). Run: ./scripts/build_web.sh"
fi

# 5. Start
if "$VENV/bin/python" -c "import socket,sys; s=socket.socket(); sys.exit(0 if s.connect_ex(('127.0.0.1', int(sys.argv[1]))) == 0 else 1)" "$PORT"; then
  die "Port $PORT is already in use. Stop the other process or run: PORT=8001 $0"
fi
cd "$ROOT/backend"
say "Starting EAGLE EYE on http://localhost:$PORT   (API docs: http://localhost:$PORT/api/v1/docs, stop with Ctrl+C)"
say "Models load in the background; the first inspection on a laptop CPU takes about 1–3 minutes."
exec "$VENV/bin/python" -m uvicorn app.main:app --host 127.0.0.1 --port "$PORT"
