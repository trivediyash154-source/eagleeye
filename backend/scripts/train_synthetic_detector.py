"""Fine-tune YOLOv8n on the SYNTHETIC cabinet dataset and export eagleeye-synth-v1.pt.

Usage:
    python scripts/build_synthetic_dataset.py
    python scripts/train_synthetic_detector.py --epochs 30

Starts from the COCO-pretrained yolov8n.pt (transfer learning). The validation metrics
written to models/eagleeye-synth-v1.metrics.json are measured on held-out SYNTHETIC renders
only; they say nothing about accuracy on real cabinet photographs.
"""
from __future__ import annotations

import argparse
import json
import shutil
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", type=Path, default=ROOT / "artifacts" / "synthetic_dataset" / "data.yaml")
    ap.add_argument("--base", type=Path, default=ROOT / "models" / "cache" / "yolov8n.pt")
    ap.add_argument("--epochs", type=int, default=30)
    ap.add_argument("--imgsz", type=int, default=640)
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--out", type=Path, default=ROOT / "models" / "eagleeye-synth-v1.pt")
    a = ap.parse_args()

    from ultralytics import YOLO

    t0 = time.time()
    model = YOLO(str(a.base))
    model.train(
        data=str(a.data), epochs=a.epochs, imgsz=a.imgsz, batch=a.batch, workers=a.workers, device="cpu",
        project=str(ROOT / "artifacts" / "training"), name="synth-v1", exist_ok=True, plots=False,
        patience=10, cos_lr=True, close_mosaic=5, mosaic=0.6, scale=0.35, degrees=2.0, fliplr=0.0,
        hsv_h=0.02, hsv_s=0.5, hsv_v=0.35, amp=False, verbose=True, seed=0,
    )
    best = ROOT / "artifacts" / "training" / "synth-v1" / "weights" / "best.pt"
    a.out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(best, a.out)
    val = YOLO(str(a.out)).val(data=str(a.data), imgsz=a.imgsz, batch=a.batch, device="cpu", plots=False, verbose=False)
    per_class = {}
    names = val.names if hasattr(val, "names") else {}
    for i, c in enumerate(val.box.ap_class_index.tolist()):
        per_class[names.get(c, str(c))] = {"mAP50": round(float(val.box.ap50[i]), 4), "mAP50_95": round(float(val.box.ap[i]), 4)}
    metrics = {
        "model": a.out.name,
        "base_weights": a.base.name,
        "dataset": "synthetic procedural renders (app/demo/synth_cabinet.py)",
        "validation_split": "held-out synthetic renders",
        "epochs_requested": a.epochs,
        "imgsz": a.imgsz,
        "training_seconds": round(time.time() - t0, 1),
        "mAP50": round(float(val.box.map50), 4),
        "mAP50_95": round(float(val.box.map), 4),
        "precision": round(float(val.box.mp), 4),
        "recall": round(float(val.box.mr), 4),
        "per_class": per_class,
        "caveat": "Measured on synthetic renders only. Not validated on real cabinet photographs.",
    }
    a.out.with_suffix(".metrics.json").write_text(json.dumps(metrics, indent=2))
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
