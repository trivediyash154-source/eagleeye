#!/usr/bin/env bash
# Build the Flutter web console and refresh the committed prebuilt bundle (frontend/prebuilt/web).
# Only maintainers need this; users can run the app with Python alone using the prebuilt bundle.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/frontend"
flutter pub get
flutter build web --release --no-web-resources-cdn
OUT="$ROOT/frontend/prebuilt/web"
rm -rf "$OUT"
mkdir -p "$OUT"
cp -R build/web/. "$OUT/"
# The CanvasKit JS renderer only loads canvaskit/{canvaskit.js,.wasm} and canvaskit/chromium/*;
# drop debug symbols and the wasm-renderer variants to keep the repository small.
find "$OUT/canvaskit" -name '*.symbols' -delete
rm -rf "$OUT/canvaskit/skwasm"* "$OUT/canvaskit/wimp"* "$OUT/canvaskit/webparagraph"
du -sh "$OUT"
