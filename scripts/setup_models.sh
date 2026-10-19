#!/usr/bin/env bash
# Download third-party model weights that are NOT stored in git (idempotent):
#   models/cache/yolov8n.pt           COCO YOLOv8n (fallback detector, training base)
#   models/cache/easyocr/*.pth        EasyOCR CRAFT detector + English recogniser
# The custom detector models/eagleeye-synth-v1.pt is committed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
C="$ROOT/models/cache"
mkdir -p "$C/easyocr"
fetch() { # url dest
  [ -s "$2" ] && return 0
  echo "[eagle-eye] downloading $(basename "$2")"
  curl -fL --retry 3 --retry-delay 2 -o "$2.part" "$1" && mv "$2.part" "$2"
}
fetch https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8n.pt "$C/yolov8n.pt"
if [ ! -s "$C/easyocr/craft_mlt_25k.pth" ]; then
  fetch https://github.com/JaidedAI/EasyOCR/releases/download/pre-v1.1.6/craft_mlt_25k.zip "$C/easyocr/craft.zip"
  unzip -o -q "$C/easyocr/craft.zip" -d "$C/easyocr" && rm -f "$C/easyocr/craft.zip"
fi
if [ ! -s "$C/easyocr/english_g2.pth" ]; then
  fetch https://github.com/JaidedAI/EasyOCR/releases/download/v1.3/english_g2.zip "$C/easyocr/en.zip"
  unzip -o -q "$C/easyocr/en.zip" -d "$C/easyocr" && rm -f "$C/easyocr/en.zip"
fi
# Plotting font used by Ultralytics (only needed for training plots); never fatal.
UCFG="${YOLO_CONFIG_DIR:-${HOME}/.config/Ultralytics}"
mkdir -p "$UCFG" 2>/dev/null || true
[ -s "$UCFG/Arial.ttf" ] || curl -fsL -o "$UCFG/Arial.ttf" https://github.com/ultralytics/assets/releases/download/v0.0.0/Arial.ttf 2>/dev/null || true
echo "[eagle-eye] model weights ready in $C"
