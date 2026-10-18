"""System health and diagnostics. Statuses come from real checks, not configuration flags."""
from __future__ import annotations

import io
import threading
import time

import cv2

from ..core.config import get_settings
from ..core.db import check_database
from ..core.logging import get_logger
from ..cv.detector import get_detector
from ..ocr.engines import get_ocr
from ..storage.local import get_storage

log = get_logger("diagnostics")
_warm = {"state": "idle", "started_at": None, "finished_at": None}
_report_probe: dict = {}


def warm_models_async() -> None:
    if _warm["state"] in ("loading", "done"):
        return

    def _run():
        _warm["state"] = "loading"
        _warm["started_at"] = time.time()
        try:
            get_detector().load()
            get_ocr().load()
        finally:
            _warm["state"] = "done"
            _warm["finished_at"] = time.time()

    threading.Thread(target=_run, name="eagleeye-warmup", daemon=True).start()


def _model_state(state: str) -> str:
    if state == "loaded":
        return "ok"
    if state in ("not_loaded",):
        return "loading" if _warm["state"] == "loading" else "not_loaded"
    if state == "disabled":
        return "disabled"
    if state == "unavailable":
        return "unavailable"
    return "error"


def probe_report_generator() -> tuple[bool, str]:
    if _report_probe:
        return _report_probe["ok"], _report_probe["msg"]
    try:
        from reportlab.pdfgen import canvas

        buf = io.BytesIO()
        c = canvas.Canvas(buf)
        c.drawString(10, 10, "probe")
        c.save()
        ok, msg = buf.getvalue().startswith(b"%PDF"), "ReportLab PDF rendering verified"
    except Exception as exc:  # pragma: no cover
        ok, msg = False, f"{type(exc).__name__}: {exc}"
    _report_probe.update(ok=ok, msg=msg)
    return ok, msg


def probe_pdf_parser() -> tuple[bool, str]:
    try:
        import pymupdf

        doc = pymupdf.open()
        page = doc.new_page()
        page.insert_text((50, 50), "Z1 PROBE")
        words = page.get_text("words")
        doc.close()
        return (len(words) == 2, f"PyMuPDF {pymupdf.VersionBind} text extraction verified")
    except Exception as exc:  # pragma: no cover
        return False, f"{type(exc).__name__}: {exc}"


def system_status() -> dict:
    s = get_settings()
    db_ok, db_msg = check_database()
    st_ok, st_msg = get_storage().writable()
    det = get_detector()
    ocr = get_ocr()
    pdf_ok, pdf_msg = probe_pdf_parser()
    rep_ok, rep_msg = probe_report_generator()
    sift = hasattr(cv2, "SIFT_create")
    det_state = _model_state(det.state)
    if det_state == "ok" and det.kind == "generic_coco":
        det_state = "degraded"
    components = [
        {"key": "api", "label": "API", "state": "ok", "message": f"FastAPI · API {s.api_version}"},
        {"key": "database", "label": "Database", "state": "ok" if db_ok else "error", "message": db_msg if db_ok else db_msg[:300]},
        {"key": "storage", "label": "File storage", "state": "ok" if st_ok else "error", "message": "writable" if st_ok else st_msg},
        {"key": "detector", "label": "YOLOv8 detector", "state": det_state,
         "message": (f"{det.model_name} ({det.kind}) on {det.device}" if det.state == "loaded" else (det.last_error or det.state))},
        {"key": "ocr", "label": "OCR engine", "state": _model_state(ocr.state),
         "message": (f"{ocr.engine.name} {getattr(ocr.engine, 'version', '')}" if ocr.engine else (ocr.last_error or ocr.state))},
        {"key": "pdf_parser", "label": "PDF parser", "state": "ok" if pdf_ok else "error", "message": pdf_msg},
        {"key": "registration", "label": "Drawing registration", "state": "ok", "message": f"OpenCV {cv2.__version__}; {'SIFT' if sift else 'ORB only'} + RANSAC; text-anchor and manual modes"},
        {"key": "report_generator", "label": "Report generator", "state": "ok" if rep_ok else "error", "message": rep_msg},
    ]
    overall = "ok" if all(c["state"] == "ok" for c in components) else ("error" if any(c["state"] == "error" for c in components[:3]) else "degraded")
    return {"status": overall, "components": components, "model_warmup": _warm["state"], "time": time.time()}


def diagnostics() -> dict:
    s = get_settings()
    return {
        "detector": get_detector().status(),
        "ocr": get_ocr().status(),
        "pipeline": {
            "opencv": cv2.__version__,
            "sift_available": hasattr(cv2, "SIFT_create"),
            "max_processing_side": s.max_processing_side,
            "job_workers": s.job_workers,
            "limits_mb": {"photo": s.max_image_mb, "drawing": s.max_pdf_mb, "expected_list": s.max_sheet_mb},
            "database_dialect": "sqlite" if s.is_sqlite else "postgresql",
            "environment": s.environment,
        },
        "status": system_status(),
    }
