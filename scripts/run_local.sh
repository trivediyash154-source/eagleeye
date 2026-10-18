#!/usr/bin/env bash
# One-command local run: backend API + Flutter web console on http://localhost:8000
#   ./scripts/run_local.sh            (uses existing venv/build if present)
#   ./scripts/run_local.sh --rebuild  (forces the Flutter web build)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY="${PYTHON:-python3.11}"
VENV="${EAGLEEYE_VENV:-$ROOT/.venv}"
if [ ! -x "$VENV/bin/python" ]; then
  "$PY" -m venv "$VENV"
  "$VENV/bin/pip" install --upgrade pip
  "$VENV/bin/pip" install -r "$ROOT/backend/requirements.txt"
fi
"$ROOT/scripts/setup_models.sh"
[ -f "$ROOT/data/demo/fixtures.json" ] || (cd "$ROOT/backend" && "$VENV/bin/python" scripts/generate_demo_fixtures.py)
if [ "${1:-}" = "--rebuild" ] || [ ! -f "$ROOT/frontend/build/web/index.html" ]; then
  (cd "$ROOT/frontend" && flutter pub get && flutter build web --release --no-web-resources-cdn)
fi
cd "$ROOT/backend"
echo "EAGLE EYE → http://localhost:${PORT:-8000}   (API docs: /api/v1/docs)"
exec "$VENV/bin/uvicorn" app.main:app --host 0.0.0.0 --port "${PORT:-8000}"
