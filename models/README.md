# Model weights

| File | In git | Purpose |
|---|---|---|
| `eagleeye-synth-v1.pt` | yes (6.5 MB) | YOLOv8n fine-tuned on **synthetic** cabinet renders. Classes: `circuit_breaker, contactor, power_supply, terminal_block, wire_marker, device_label, earth_bar`. |
| `eagleeye-synth-v1.metrics.json` | yes | Validation metrics on held-out **synthetic** renders (mAP50 0.995, mAP50-95 0.938). Not a real-world accuracy figure. |
| `cache/yolov8n.pt` | no | COCO-pretrained YOLOv8n: base for training and fallback detector (no cabinet classes). |
| `cache/easyocr/*.pth` | no | EasyOCR CRAFT detector + English recognition weights. |

Download the third-party weights with `./scripts/setup_models.sh` (GitHub releases).

## Selection at runtime

1. `EAGLEEYE_DETECTOR_WEIGHTS` (default `models/eagleeye-synth-v1.pt`)
2. `EAGLEEYE_DETECTOR_FALLBACK_WEIGHTS` (default `models/cache/yolov8n.pt`) — reported as
   `generic_coco`; component presence/type checks then return UNCERTAIN with that reason.

Model Diagnostics in the console shows which weights are loaded, device, classes, thresholds,
timings, limitations and a live test button.

## Training on real cabinets (recommended next step)

Annotate real cabinet photos in YOLO format with the same class names (Roboflow/CVAT/Label Studio),
then:

```bash
cd backend
python scripts/train_synthetic_detector.py --data /path/to/data.yaml --epochs 80 \
       --out ../models/eagleeye-real-v1.pt
EAGLEEYE_DETECTOR_WEIGHTS=../models/eagleeye-real-v1.pt uvicorn app.main:app
```
Mixing synthetic renders (`scripts/build_synthetic_dataset.py`) with real images is a reasonable
start; validate on held-out *real* photos before trusting presence FAIL verdicts.

## OCR engines

`EAGLEEYE_OCR_ENGINE=auto` tries PaddleOCR first, then EasyOCR. PaddleOCR is not installed by
default (its model hosts were unreachable in the build environment); install `paddlepaddle paddleocr`
and allow its model download to enable it. The active engine and the reason any engine is
unavailable are shown in Model Diagnostics.
