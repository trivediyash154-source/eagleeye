#!/usr/bin/env bash
# EAGLE EYE — one-command local run (Linux / macOS):  API + web console on http://localhost:8000
#
#   ./scripts/run_local.sh               first run: creates .venv, installs deps, downloads model weights
#   ./scripts/run_local.sh --rebuild     also rebuilds the Flutter web console (needs Flutter 3.47+)
#   PORT=8080 ./scripts/run_local.sh     fixed port (default: 8000, or the next free port up to 8010)
#
# Requirements: curl, unzip, ~6 GB free disk (PyTorch). Uses Python 3.11–3.13 if installed; otherwise
# installs a private Python 3.11 with uv (https://docs.astral.sh/uv) into .tools/ — nothing system-wide.
# Supported: Linux x86_64/arm64, macOS 14+ on Apple Silicon. Windows: scripts\run_local.ps1.
# Flutter is NOT required: a prebuilt web console is committed in frontend/prebuilt/web.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-}"
VENV="${EAGLEEYE_VENV:-$ROOT/.venv}"

say() { printf '\033[1;36m[eagle-eye]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[eagle-eye] %s\033[0m\n' "$*" >&2; exit 1; }

TOOLS="$ROOT/.tools"

find_uv() {
  for p in "$TOOLS/uv" "$TOOLS/bin/uv"; do [ -x "$p" ] && { echo "$p"; return 0; }; done
  command -v uv 2>/dev/null
}

# Prints the path of a Python 3.11–3.13 interpreter; installs a private 3.11 with uv when none is found.
pick_python() {
  if [ -n "${PYTHON:-}" ]; then echo "$PYTHON"; return; fi
  for c in python3.11 python3.12 python3.13 python3; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if (3,11) <= sys.version_info[:2] <= (3,13) else 1)' 2>/dev/null; then
      echo "$c"; return
    fi
  done
  local uv
  if ! uv="$(find_uv)"; then
    say "Python 3.11–3.13 not found: installing uv into .tools/ to provide a private Python 3.11" >&2
    curl -LsSf https://github.com/astral-sh/uv/releases/latest/download/uv-installer.sh | env UV_INSTALL_DIR="$TOOLS" UV_NO_MODIFY_PATH=1 INSTALLER_NO_MODIFY_PATH=1 sh >&2 \
      || die "Could not install uv. Install Python 3.11 yourself (python.org or 'brew install python@3.11') and re-run."
    uv="$(find_uv)" || die "uv was installed but not found in $TOOLS"
  fi
  say "Installing Python 3.11 with uv (one-time download, ~20 MB)" >&2
  UV_PYTHON_INSTALL_DIR="$TOOLS/python" "$uv" python install --no-bin 3.11 >&2 || die "uv could not install Python 3.11"
  UV_PYTHON_INSTALL_DIR="$TOOLS/python" "$uv" python find 3.11
}

command -v curl >/dev/null || die "curl is required"
command -v unzip >/dev/null || die "unzip is required"

# PyTorch 2.14 / OpenCV 5 ship macOS wheels for Apple Silicon on macOS 14+ only.
if [ "$(uname -s)" = Darwin ]; then
  if [ "$(uname -m)" != arm64 ]; then
    if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = 1 ]; then
      die "This Terminal runs under Rosetta (x86_64). Run natively instead:  arch -arm64 ./scripts/run_local.sh"
    fi
    die "Intel Macs cannot install PyTorch 2.14 / OpenCV 5 natively. Use Docker instead:  docker compose up --build"
  fi
  MACOS="$(sw_vers -productVersion)"
  [ "${MACOS%%.*}" -ge 14 ] || die "macOS 14 (Sonoma) or newer is required for the PyTorch build used here; this Mac runs macOS $MACOS."
fi

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
# A port counts as busy if anything answers on it over IPv4 or IPv6 (browsers may try ::1 for "localhost").
port_busy() {
  "$VENV/bin/python" - "$1" <<'PY'
import socket, sys
port = int(sys.argv[1])
for family, host in ((socket.AF_INET, "127.0.0.1"), (socket.AF_INET6, "::1")):
    try:
        with socket.socket(family) as s:
            s.settimeout(0.5)
            if s.connect_ex((host, port)) == 0:
                sys.exit(0)
    except OSError:
        pass
sys.exit(1)
PY
}
if [ -n "$PORT" ]; then
  port_busy "$PORT" && die "Port $PORT is already in use. Stop the other program or choose another: PORT=8001 $0"
else
  PORT=8000
  while port_busy "$PORT"; do
    [ "$PORT" -ge 8010 ] && die "Ports 8000-8010 are all in use. Choose a free one: PORT=9000 $0"
    say "Port $PORT is used by another program; trying $((PORT + 1))"
    PORT=$((PORT + 1))
  done
fi
cd "$ROOT/backend"
say "Starting EAGLE EYE — open http://localhost:$PORT in your browser   (API docs: /api/v1/docs, stop with Ctrl+C)"
say "Models load in the background; the first inspection on a laptop CPU takes about 1–3 minutes."
exec "$VENV/bin/python" -m uvicorn app.main:app --host 127.0.0.1 --port "$PORT"
