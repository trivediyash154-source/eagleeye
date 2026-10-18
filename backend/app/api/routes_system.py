from __future__ import annotations

import base64
import time

from fastapi import APIRouter, File, UploadFile

from ..core.config import get_settings
from ..core.errors import ApiError, bad_request
from ..core.logging import ring_handler
from ..cv import draw
from ..cv.detector import get_detector
from ..cv.preprocess import ImageDecodeError, decode_image, encode_jpeg, prepare, thumbnail
from ..inspection.pipeline import CHECK_INFO
from ..ocr.engines import get_ocr
from ..services import diagnostics as diag

router = APIRouter(tags=["system"])


@router.get("/health", summary="Liveness probe")
def health():
    s = get_settings()
    return {"status": "ok", "service": "eagleeye-api", "api_version": s.api_version, "time": time.time()}


@router.get("/system/status", summary="Readiness of every subsystem (real checks)")
def system_status():
    return diag.system_status()


@router.get("/system/diagnostics", summary="Detector, OCR and pipeline diagnostics")
def system_diagnostics():
    return diag.diagnostics()


@router.post("/system/models/load", summary="Load detector and OCR models now")
def load_models():
    det_ok = get_detector().load()
    ocr_ok = get_ocr().load()
    return {"detector_loaded": det_ok, "ocr_loaded": ocr_ok, "status": diag.system_status()}


@router.get("/system/logs", summary="Recent structured operational events (redacted)")
def logs(level: str | None = None, component: str | None = None, limit: int = 200):
    return {"items": ring_handler.entries(level, component, max(1, min(limit, 1000)))}


@router.get("/system/checks", summary="Inspection checks and their availability with the loaded models")
def checks():
    det = get_detector()
    ocr = get_ocr()
    out = []
    for key, info in CHECK_INFO.items():
        available, note = True, None
        if key in ("component_presence", "component_type"):
            if det.state != "loaded":
                available, note = False, "detector not loaded"
            elif not det.supported_cabinet_classes:
                available, note = False, "loaded detector has no cabinet component classes (generic COCO model)"
        if key in ("device_label", "ferrule_label") and ocr.state != "loaded":
            available, note = False, "OCR engine not loaded"
        out.append({"key": key, **info, "available": available, "note": note})
    return {"items": out}


def _read_test_image(data: bytes | None):
    s = get_settings()
    if data:
        try:
            return decode_image(data).bgr, "uploaded image"
        except ImageDecodeError as exc:
            raise bad_request("unreadable_image", str(exc)) from exc
    sample = s.demo_dir / "CAB-07_cabinet_photo_v1_SYNTHETIC.jpg"
    if not sample.is_file():
        raise bad_request("no_test_image", "Upload a test image (demo fixtures are not installed).")
    return decode_image(sample.read_bytes()).bgr, f"bundled synthetic fixture {sample.name}"


def _data_url(img) -> str:
    return "data:image/jpeg;base64," + base64.b64encode(encode_jpeg(thumbnail(img, 1400), 82)).decode()


@router.post("/system/diagnostics/detector-test", summary="Run the loaded detector on a test image")
async def detector_test(file: UploadFile | None = File(default=None)):
    data = await file.read() if file else None
    img, source = _read_test_image(data)
    det = get_detector()
    if not det.load():
        raise ApiError(503, "detector_unavailable", det.last_error or "detector unavailable")
    pp = prepare(img)
    run = det.detect(pp.processed)
    vis = img.copy()
    out = []
    for d in run.detections:
        box = pp.box_to_original(d.box)
        if d.confidence >= run.conf_threshold:
            draw.box(vis, box, draw.CLASS_BGR.get(d.class_name, (200, 200, 200)), f"{d.class_name} {d.confidence:.2f}")
        out.append({"class_name": d.class_name, "confidence": round(d.confidence, 4), "bbox": [round(v, 1) for v in box], "above_threshold": d.confidence >= run.conf_threshold})
    return {"source": source, "model": run.model_name, "kind": det.kind, "device": run.device, "duration_ms": run.duration_ms, "tiles": run.tiles,
            "conf_threshold": run.conf_threshold, "detections": out, "annotated_image": _data_url(vis)}


@router.post("/system/diagnostics/ocr-test", summary="Run the OCR engine on a test image")
async def ocr_test(file: UploadFile | None = File(default=None)):
    data = await file.read() if file else None
    img, source = _read_test_image(data)
    ocr = get_ocr()
    if not ocr.load():
        raise ApiError(503, "ocr_unavailable", ocr.last_error or "OCR unavailable")
    pp = prepare(img)
    t0 = time.time()
    regions = ocr.read(pp.processed, canvas=get_settings().ocr_full_image_canvas)
    ms = int((time.time() - t0) * 1000)
    vis = img.copy()
    out = []
    for r in regions:
        box = pp.box_to_original(r.box)
        draw.box(vis, box, (255, 220, 80), f"{r.text} {r.confidence:.2f}")
        out.append({"text": r.text, "confidence": round(r.confidence, 4), "bbox": [round(v, 1) for v in box]})
    return {"source": source, "engine": ocr.engine.name, "duration_ms": ms, "regions": out, "annotated_image": _data_url(vis)}
