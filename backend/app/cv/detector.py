"""YOLOv8 detector service (Ultralytics).

Weights selection:
  1. ``EAGLEEYE_DETECTOR_WEIGHTS`` (default ``models/eagleeye-synth-v1.pt``) — cabinet classes.
  2. ``EAGLEEYE_DETECTOR_FALLBACK_WEIGHTS`` (default ``models/cache/yolov8n.pt``) — generic COCO
     model. It has NO electrical-cabinet classes; presence checks become UNCERTAIN with that
     limitation stated rather than inventing detections.

Small objects: besides a full-image pass, high-resolution images are split into overlapping
tiles. Tile detections touching an interior tile border are dropped (the neighbouring tile or
the full pass sees the whole object) and the union is reduced with class-wise NMS. All boxes
are returned in the coordinates of the image passed in.
"""
from __future__ import annotations

import json
import os
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from ..core.config import get_settings
from ..core.logging import get_logger
from ..core.util import iso, utcnow

log = get_logger("cv.detector")
os.environ.setdefault("YOLO_AUTOINSTALL", "false")  # never pip-install at runtime
os.environ.setdefault("YOLO_OFFLINE", "1")  # no telemetry / online checks

# Canonical cabinet classes the verification engine understands.
CABINET_CLASSES = {"circuit_breaker", "contactor", "power_supply", "terminal_block", "wire_marker", "device_label", "earth_bar", "relay"}


@dataclass
class Det:
    class_id: int
    class_name: str
    confidence: float
    box: tuple[float, float, float, float]
    source: str = "full"


@dataclass
class DetectionRun:
    detections: list[Det]
    duration_ms: int
    tiles: int
    model_name: str
    device: str
    imgsz: int
    conf_threshold: float
    iou_threshold: float
    min_store_conf: float
    params: dict = field(default_factory=dict)


def nms(boxes: np.ndarray, scores: np.ndarray, iou_thr: float) -> list[int]:
    if len(boxes) == 0:
        return []
    x0, y0, x1, y1 = boxes[:, 0], boxes[:, 1], boxes[:, 2], boxes[:, 3]
    areas = np.maximum(0, x1 - x0) * np.maximum(0, y1 - y0)
    order = scores.argsort()[::-1]
    keep: list[int] = []
    while order.size > 0:
        i = int(order[0])
        keep.append(i)
        xx0 = np.maximum(x0[i], x0[order[1:]])
        yy0 = np.maximum(y0[i], y0[order[1:]])
        xx1 = np.minimum(x1[i], x1[order[1:]])
        yy1 = np.minimum(y1[i], y1[order[1:]])
        inter = np.maximum(0, xx1 - xx0) * np.maximum(0, yy1 - yy0)
        iou = inter / np.maximum(1e-9, areas[i] + areas[order[1:]] - inter)
        # also suppress boxes mostly contained in the kept box (partial duplicates)
        contain = inter / np.maximum(1e-9, areas[order[1:]])
        order = order[1:][(iou <= iou_thr) & (contain <= 0.85)]
    return keep


def make_tiles(w: int, h: int, tile: int, overlap: float) -> list[tuple[int, int, int, int]]:
    if max(w, h) <= tile:
        return []
    step = max(1, int(tile * (1 - overlap)))
    xs = list(range(0, max(1, w - tile) + 1, step))
    ys = list(range(0, max(1, h - tile) + 1, step))
    if xs[-1] + tile < w:
        xs.append(w - tile)
    if ys[-1] + tile < h:
        ys.append(h - tile)
    out = []
    for y in ys:
        for x in xs:
            out.append((max(0, x), max(0, y), min(w, x + tile), min(h, y + tile)))
    return out


class DetectorService:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._model = None
        self.state = "not_loaded"
        self.kind = "none"
        self.weights_path: Path | None = None
        self.model_name = ""
        self.device = ""
        self.class_names: dict[int, str] = {}
        self.last_error: str | None = None
        self.loaded_at = None
        self.load_ms: int | None = None
        self.last_inference_ms: int | None = None
        self.last_inference_at = None
        self.metrics: dict | None = None

    # -- loading -----------------------------------------------------------
    def _resolve_device(self, requested: str) -> str:
        if requested != "auto":
            return requested
        try:
            import torch

            if torch.cuda.is_available():
                return "cuda:0"
            if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
                return "mps"
        except Exception:
            pass
        return "cpu"

    def load(self) -> bool:
        with self._lock:
            if self._model is not None:
                return True
            s = get_settings()
            candidates = []
            if s.detector_weights:
                candidates.append((Path(s.detector_weights), "custom"))
            if s.detector_fallback_weights:
                candidates.append((Path(s.detector_fallback_weights), "generic_coco"))
            chosen = next(((p, k) for p, k in candidates if p.is_file()), None)
            if chosen is None:
                self.state = "unavailable"
                self.last_error = "No detector weights found. Expected " + " or ".join(str(p) for p, _ in candidates) + ". See models/README.md."
                log.warning(self.last_error)
                return False
            path, kind = chosen
            t0 = time.time()
            try:
                from ultralytics import YOLO

                model = YOLO(str(path))
                self.device = self._resolve_device(s.detector_device)
                # warm-up forward pass validates that the weights actually run
                model.predict(np.zeros((64, 64, 3), np.uint8), imgsz=64, device=self.device, verbose=False)
                self._model = model
                self.class_names = {int(k): str(v) for k, v in model.names.items()}
                self.weights_path = path
                self.model_name = path.name
                cab = CABINET_CLASSES & set(self.class_names.values())
                self.kind = kind if (kind == "custom" and cab) else ("generic_coco" if not cab else kind)
                self.state = "loaded"
                self.loaded_at = utcnow()
                self.load_ms = int((time.time() - t0) * 1000)
                self.last_error = None
                mfile = path.with_suffix(".metrics.json")
                self.metrics = json.loads(mfile.read_text(encoding="utf-8")) if mfile.is_file() else None
                log.info("Detector loaded", extra={"ctx": {"weights": path.name, "device": self.device, "classes": len(self.class_names), "kind": self.kind}})
                return True
            except Exception as exc:
                self.state = "error"
                self.last_error = f"{type(exc).__name__}: {exc}"
                log.error("Detector failed to load: %s", self.last_error)
                return False

    @property
    def supported_cabinet_classes(self) -> set[str]:
        return CABINET_CLASSES & set(self.class_names.values())

    def supports(self, canonical_class: str | None) -> bool:
        return bool(canonical_class) and canonical_class in self.supported_cabinet_classes

    def status(self) -> dict:
        s = get_settings()
        configured = Path(s.detector_weights) if s.detector_weights else None
        fallback = Path(s.detector_fallback_weights) if s.detector_fallback_weights else None
        return {
            "state": self.state,
            "kind": self.kind,
            "model_name": self.model_name or None,
            "weights_path": str(self.weights_path) if self.weights_path else None,
            "configured_weights": str(configured) if configured else None,
            "configured_weights_exists": bool(configured and configured.is_file()),
            "fallback_weights": str(fallback) if fallback else None,
            "fallback_weights_exists": bool(fallback and fallback.is_file()),
            "device": self.device or None,
            "classes": [self.class_names[k] for k in sorted(self.class_names)],
            "supported_cabinet_classes": sorted(self.supported_cabinet_classes),
            "conf_threshold": s.detector_conf,
            "iou_threshold": s.detector_iou,
            "min_store_conf": s.detector_min_store_conf,
            "imgsz": s.detector_imgsz,
            "tiling": {"enabled": s.detector_tiling, "tile_size": s.detector_tile_size, "overlap": s.detector_tile_overlap},
            "load_ms": self.load_ms,
            "loaded_at": iso(self.loaded_at),
            "last_inference_ms": self.last_inference_ms,
            "last_inference_at": iso(self.last_inference_at),
            "last_error": self.last_error,
            "training_metrics": self.metrics,
            "limitations": self._limitations(),
        }

    def _limitations(self) -> list[str]:
        if self.kind == "generic_coco":
            return [
                "Generic COCO-pretrained YOLOv8 weights are loaded. They contain no electrical-cabinet classes "
                "(breakers, contactors, terminals, ferrules), so component presence/type checks report UNCERTAIN.",
                "Add cabinet-specific weights at EAGLEEYE_DETECTOR_WEIGHTS to enable presence/type verification.",
            ]
        if self.kind == "custom" and self.metrics and "synthetic" in json.dumps(self.metrics).lower():
            return [
                "The loaded weights were trained ONLY on procedurally generated (synthetic) cabinet renders.",
                "They are suitable for the bundled demonstration fixtures and for exercising the pipeline, "
                "but have not been validated on real cabinet photographs.",
            ]
        return []

    # -- inference ---------------------------------------------------------
    def detect(self, bgr: np.ndarray, conf: float | None = None, iou: float | None = None, tiling: bool | None = None) -> DetectionRun:
        if not self.load():
            raise RuntimeError(self.last_error or "detector unavailable")
        s = get_settings()
        conf_thr = s.detector_conf if conf is None else conf
        iou_thr = s.detector_iou if iou is None else iou
        store_conf = min(s.detector_min_store_conf, conf_thr)
        use_tiles = s.detector_tiling if tiling is None else tiling
        h, w = bgr.shape[:2]
        t0 = time.time()
        dets: list[Det] = []
        model = self._model
        with self._lock:
            res = model.predict(bgr, imgsz=s.detector_imgsz, conf=store_conf, iou=iou_thr, device=self.device, verbose=False)
            dets.extend(self._to_dets(res[0], 0, 0, "full"))
            tiles = make_tiles(w, h, s.detector_tile_size, s.detector_tile_overlap) if use_tiles else []
            for i in range(0, len(tiles), 4):
                batch = tiles[i:i + 4]
                crops = [bgr[y0:y1, x0:x1] for (x0, y0, x1, y1) in batch]
                results = model.predict(crops, imgsz=s.detector_imgsz, conf=store_conf, iou=iou_thr, device=self.device, verbose=False)
                for (x0, y0, x1, y1), r in zip(batch, results):
                    for d in self._to_dets(r, x0, y0, "tile"):
                        bx0, by0, bx1, by1 = d.box
                        m = 3.0
                        touches_inner = (bx0 - x0 < m and x0 > 0) or (by0 - y0 < m and y0 > 0) or (x1 - bx1 < m and x1 < w) or (y1 - by1 < m and y1 < h)
                        if not touches_inner:
                            dets.append(d)
        merged: list[Det] = []
        for cname in {d.class_name for d in dets}:
            group = [d for d in dets if d.class_name == cname]
            boxes = np.array([d.box for d in group], np.float64)
            scores = np.array([d.confidence for d in group], np.float64)
            for k in nms(boxes, scores, iou_thr):
                merged.append(group[k])
        merged.sort(key=lambda d: (d.class_name, -d.confidence))
        ms = int((time.time() - t0) * 1000)
        self.last_inference_ms = ms
        self.last_inference_at = utcnow()
        return DetectionRun(
            detections=merged, duration_ms=ms, tiles=len(tiles), model_name=self.model_name, device=self.device, imgsz=s.detector_imgsz,
            conf_threshold=conf_thr, iou_threshold=iou_thr, min_store_conf=store_conf,
            params={"tile_size": s.detector_tile_size, "tile_overlap": s.detector_tile_overlap, "tiling": use_tiles},
        )

    def _to_dets(self, r, ox: int, oy: int, source: str) -> list[Det]:
        out = []
        if r.boxes is None or len(r.boxes) == 0:
            return out
        xyxy = r.boxes.xyxy.cpu().numpy()
        confs = r.boxes.conf.cpu().numpy()
        clss = r.boxes.cls.cpu().numpy().astype(int)
        for (x0, y0, x1, y1), c, k in zip(xyxy, confs, clss):
            out.append(Det(int(k), self.class_names.get(int(k), str(k)), float(c), (float(x0 + ox), float(y0 + oy), float(x1 + ox), float(y1 + oy)), source))
        return out


_detector: DetectorService | None = None
_dlock = threading.Lock()


def get_detector() -> DetectorService:
    global _detector
    with _dlock:
        if _detector is None:
            _detector = DetectorService()
        return _detector
