#!/usr/bin/env bash
# Download the third-party model weights that are NOT stored in git:
#   - YOLOv8n COCO weights (fallback detector + base for training)
#   - EasyOCR detection (CRAFT) and English recognition weights
# The custom synthetic detector (models/eagleeye-synth-v1.pt) IS in git.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/models/cache/easyocr"
cd "$ROOT/models/cache"
[ -f yolov8n.pt ] || curl -fL -o yolov8n.pt https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8n.pt
cd easyocr
if [ ! -f craft_mlt_25k.pth ]; then curl -fL -o craft.zip https://github.com/JaidedAI/EasyOCR/releases/download/pre-v1.1.6/craft_mlt_25k.zip && unzip -o -q craft.zip && rm craft.zip; fi
if [ ! -f english_g2.pth ]; then curl -fL -o en.zip https://github.com/JaidedAI/EasyOCR/releases/download/v1.3/english_g2.zip && unzip -o -q en.zip && rm en.zip; fi
# Ultralytics plotting font (avoids a runtime download from ultralytics.com)
mkdir -p "${HOME}/.config/Ultralytics"
[ -f "${HOME}/.config/Ultralytics/Arial.ttf" ] || curl -fL -o "${HOME}/.config/Ultralytics/Arial.ttf" https://github.com/ultralytics/assets/releases/download/v0.0.0/Arial.ttf || true
echo "Model weights ready in $ROOT/models/cache"
