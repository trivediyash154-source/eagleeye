"""OCR engine adapters and the OCR service.

PaddleOCR is the preferred engine; EasyOCR is the alternative. With ``EAGLEEYE_OCR_ENGINE=auto``
PaddleOCR is tried first and EasyOCR is used if PaddleOCR is not installed or cannot load its
models. The service reports exactly which engine is active and why the other is not.

Both engines read real image pixels; there is no simulated OCR path.
"""
from __future__ import annotations

import string
import threading
import time
from dataclasses import dataclass

import cv2
import numpy as np

from ..core.config import get_settings
from ..core.logging import get_logger
from ..core.util import iso, utcnow
from .normalize import normalize

log = get_logger("ocr")


@dataclass
class TextRegion:
    polygon: list[list[float]]
    text: str
    confidence: float

    @property
    def box(self) -> tuple[float, float, float, float]:
        xs = [p[0] for p in self.polygon]
        ys = [p[1] for p in self.polygon]
        return (min(xs), min(ys), max(xs), max(ys))


def default_allowlist() -> str:
    s = get_settings()
    chars = string.ascii_uppercase + string.digits + "-:/.+"
    if s.ocr_exclude_io:
        chars = chars.replace("I", "").replace("O", "")
    return chars


class EasyOcrEngine:
    name = "easyocr"

    def __init__(self) -> None:
        import easyocr

        s = get_settings()
        self.version = getattr(easyocr, "__version__", "unknown")
        self.reader = easyocr.Reader(
            s.ocr_languages, gpu=s.ocr_gpu, model_storage_directory=str(s.easyocr_model_dir),
            download_enabled=s.ocr_allow_download, verbose=False,
        )

    def read(self, img: np.ndarray, allowlist: str | None, canvas: int | None = None, detail_only_recognition: bool = False) -> list[TextRegion]:
        kw = {"allowlist": allowlist} if allowlist else {}
        if canvas:
            kw["canvas_size"] = canvas
        if detail_only_recognition:
            h, w = img.shape[:2]
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY) if img.ndim == 3 else img
            res = self.reader.recognize(gray, horizontal_list=[[0, w, 0, h]], free_list=[], **{k: v for k, v in kw.items() if k == "allowlist"})
        else:
            res = self.reader.readtext(img, **kw)
        out = []
        for poly, text, conf in res:
            out.append(TextRegion([[float(x), float(y)] for x, y in poly], str(text), float(conf)))
        return out


class PaddleOcrEngine:
    name = "paddleocr"

    def __init__(self) -> None:
        from paddleocr import PaddleOCR  # noqa: F401  (ImportError reported by the service)

        import paddleocr

        self.version = getattr(paddleocr, "__version__", "unknown")
        try:  # PaddleOCR 3.x
            self.ocr = PaddleOCR(lang="en", use_doc_orientation_classify=False, use_doc_unwarping=False, use_textline_orientation=True)
            self.api = 3
        except TypeError:  # PaddleOCR 2.x
            self.ocr = PaddleOCR(lang="en", use_angle_cls=True, show_log=False)
            self.api = 2

    def read(self, img: np.ndarray, allowlist: str | None, canvas: int | None = None, detail_only_recognition: bool = False) -> list[TextRegion]:
        out: list[TextRegion] = []
        if self.api == 3:
            for page in self.ocr.predict(img):
                data = page.json.get("res", page.json) if hasattr(page, "json") else page
                for poly, text, conf in zip(data.get("rec_polys", []), data.get("rec_texts", []), data.get("rec_scores", [])):
                    out.append(TextRegion([[float(x), float(y)] for x, y in poly], str(text), float(conf)))
        else:
            res = self.ocr.ocr(img, cls=True) or []
            for line in res[0] or []:
                poly, (text, conf) = line
                out.append(TextRegion([[float(x), float(y)] for x, y in poly], str(text), float(conf)))
        if allowlist:
            allowed = set(allowlist)
            out = [TextRegion(r.polygon, "".join(ch for ch in r.text.upper() if ch in allowed or ch == " "), r.confidence) for r in out]
        return out


class OcrService:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.engine = None
        self.state = "not_loaded"
        self.engine_errors: dict[str, str] = {}
        self.last_error: str | None = None
        self.loaded_at = None
        self.load_ms: int | None = None
        self.last_success_at = None
        self.last_duration_ms: int | None = None

    def load(self) -> bool:
        with self._lock:
            if self.engine is not None:
                return True
            s = get_settings()
            pref = s.ocr_engine.lower()
            if pref == "none":
                self.state = "disabled"
                self.last_error = "OCR disabled by configuration (EAGLEEYE_OCR_ENGINE=none)"
                return False
            order = {"auto": ["paddle", "easyocr"], "paddle": ["paddle"], "paddleocr": ["paddle"], "easyocr": ["easyocr"]}.get(pref, ["paddle", "easyocr"])
            t0 = time.time()
            for name in order:
                try:
                    eng = PaddleOcrEngine() if name == "paddle" else EasyOcrEngine()
                    # smoke test on a synthetic glyph image proves the models really run
                    probe = np.full((48, 160, 3), 255, np.uint8)
                    cv2.putText(probe, "AB12", (10, 36), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (0, 0, 0), 2)
                    eng.read(probe, None)
                    self.engine = eng
                    self.state = "loaded"
                    self.loaded_at = utcnow()
                    self.load_ms = int((time.time() - t0) * 1000)
                    self.last_error = None
                    log.info("OCR engine loaded", extra={"ctx": {"engine": eng.name, "version": eng.version}})
                    return True
                except ImportError as exc:
                    self.engine_errors[name] = f"not installed ({exc.name or exc})"
                except Exception as exc:
                    self.engine_errors[name] = f"{type(exc).__name__}: {str(exc)[:300]}"
                    log.warning("OCR engine %s failed to initialise: %s", name, self.engine_errors[name])
            self.state = "unavailable"
            self.last_error = "; ".join(f"{k}: {v}" for k, v in self.engine_errors.items())
            return False

    def status(self) -> dict:
        s = get_settings()
        return {
            "state": self.state,
            "engine": self.engine.name if self.engine else None,
            "engine_version": getattr(self.engine, "version", None) if self.engine else None,
            "preference": s.ocr_engine,
            "languages": s.ocr_languages,
            "gpu": s.ocr_gpu,
            "allowlist": default_allowlist(),
            "exclude_io": s.ocr_exclude_io,
            "engine_errors": self.engine_errors,
            "model_dir": str(s.easyocr_model_dir),
            "load_ms": self.load_ms,
            "loaded_at": iso(self.loaded_at),
            "last_success_at": iso(self.last_success_at),
            "last_duration_ms": self.last_duration_ms,
            "last_error": self.last_error,
        }

    def read(self, img: np.ndarray, allowlist: str | None = "default", canvas: int | None = None, recognition_only: bool = False) -> list[TextRegion]:
        if not self.load():
            raise RuntimeError(self.last_error or "OCR unavailable")
        al = default_allowlist() if allowlist == "default" else allowlist
        t0 = time.time()
        try:
            with self._lock:
                res = self.engine.read(img, al, canvas=canvas, detail_only_recognition=recognition_only)
        except Exception as exc:
            self.last_error = f"{type(exc).__name__}: {exc}"
            raise
        self.last_duration_ms = int((time.time() - t0) * 1000)
        self.last_success_at = utcnow()
        return res

    def read_crop_variants(self, crop: np.ndarray, upscale: float | None = None, try_rotations: bool = True) -> list[dict]:
        """Recognise a small crop under several preprocessing variants.

        Returns one entry per variant (text, normalised text, confidence, polygon in crop px).
        The caller selects by OCR confidence — never by similarity to the expected value.
        """
        s = get_settings()
        up = upscale or s.ocr_crop_upscale
        h, w = crop.shape[:2]
        if h < 4 or w < 4:
            return []
        big = cv2.resize(crop, (int(w * up), int(h * up)), interpolation=cv2.INTER_CUBIC)
        gray = cv2.cvtColor(big, cv2.COLOR_BGR2GRAY)
        clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(4, 4)).apply(gray)
        _, otsu = cv2.threshold(cv2.GaussianBlur(gray, (3, 3), 0), 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        variants: list[tuple[str, np.ndarray, int]] = [
            ("upscaled", big, 0),
            ("clahe", cv2.cvtColor(clahe, cv2.COLOR_GRAY2BGR), 0),
            ("otsu", cv2.cvtColor(otsu, cv2.COLOR_GRAY2BGR), 0),
        ]
        if try_rotations and h > w * 1.6:
            rot = cv2.rotate(big, cv2.ROTATE_90_CLOCKWISE)
            variants.append(("rot90", rot, 90))
            variants.append(("rot270", cv2.rotate(big, cv2.ROTATE_90_COUNTERCLOCKWISE), 270))
        out = []
        for name, img, rot in variants:
            try:
                regions = self.read(img)
            except Exception as exc:
                out.append({"variant": name, "error": str(exc)})
                continue
            if not regions:
                out.append({"variant": name, "text": "", "normalized": "", "confidence": 0.0})
                continue
            # merge regions left-to-right into one reading for the crop
            regions.sort(key=lambda r: (r.box[0] if rot == 0 else r.box[1]))
            text = " ".join(r.text for r in regions).strip()
            conf = float(np.mean([r.confidence for r in regions]))
            norm, steps = normalize(text)
            xs = [p[0] / up for r in regions for p in r.polygon]
            ys = [p[1] / up for r in regions for p in r.polygon]
            box = [min(xs), min(ys), max(xs), max(ys)] if rot == 0 else [0.0, 0.0, float(w), float(h)]
            out.append({"variant": name, "text": text, "normalized": norm, "steps": steps, "confidence": round(conf, 4), "box": box, "regions": len(regions)})
        return out


_ocr: OcrService | None = None
_olock = threading.Lock()


def get_ocr() -> OcrService:
    global _ocr
    with _olock:
        if _ocr is None:
            _ocr = OcrService()
        return _ocr
