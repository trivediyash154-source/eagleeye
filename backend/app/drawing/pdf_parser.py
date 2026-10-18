"""GA drawing parser (PyMuPDF).

Coordinate convention: PDF points, origin at the top-left of the page, y increasing downward
(PyMuPDF's page coordinates). Rendered images use ``render_scale`` pixels per point.

What this parser can and cannot do:
  * Vector PDFs: text words and rectangles are extracted exactly from the drawing.
  * Raster PDFs (scans): the page is rendered at 300 DPI and read with OCR; rectangles are
    found by contour detection. Results are less reliable and flagged with warnings.
  * Zones are found from zone labels (``Z1``, ``ZONE 3`` ...) inside enclosing frames. If none
    exist, zones can be derived from component positions or defined manually by an inspector.
  * Arbitrary engineering drawings are not guaranteed to be interpretable automatically.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

import cv2
import numpy as np

from ..core.logging import get_logger

log = get_logger("drawing.parser")

ZONE_RE = re.compile(r"^(?:Z|ZONE)[-_ ]?(\d{1,3}[A-Z]?)$", re.I)
DASH_CHARS = "‐‑‒–—−"


def _norm(t: str) -> str:
    t = t.strip().upper()
    for ch in DASH_CHARS:
        t = t.replace(ch, "-")
    return t


class PdfError(ValueError):
    pass


def _open(data: bytes):
    import pymupdf

    try:
        doc = pymupdf.open(stream=data, filetype="pdf")
    except Exception as exc:
        raise PdfError(f"file is not a readable PDF: {exc}") from exc
    if doc.needs_pass:
        raise PdfError("PDF is password protected")
    if doc.page_count == 0:
        raise PdfError("PDF has no pages")
    return doc


def inspect_pdf(data: bytes) -> dict:
    doc = _open(data)
    pages = []
    warnings = []
    for i, page in enumerate(doc):
        words = page.get_text("words")
        try:
            n_draw = len(page.get_drawings())
        except Exception:
            n_draw = 0
        n_img = len(page.get_images(full=True))
        kind = classify_page(len(words), n_draw, n_img)
        pages.append({
            "index": i,
            "width_pt": round(page.rect.width, 2),
            "height_pt": round(page.rect.height, 2),
            "words": len(words),
            "vector_paths": n_draw,
            "images": n_img,
            "kind": kind,
            "text_extractable": len(words) > 0,
        })
        if kind == "raster":
            warnings.append({"page": i, "code": "raster_page", "message": f"Page {i + 1} has no text layer; OCR will be used and zone extraction may be unreliable."})
        if kind == "empty":
            warnings.append({"page": i, "code": "empty_page", "message": f"Page {i + 1} appears empty."})
    meta = {k: v for k, v in (doc.metadata or {}).items() if v}
    out = {"page_count": doc.page_count, "pages": pages, "metadata": meta, "warnings": warnings}
    doc.close()
    return out


def classify_page(words: int, paths: int, images: int) -> str:
    if words >= 5 and paths >= 5:
        return "vector"
    if words >= 5 and images:
        return "mixed"
    if words >= 5:
        return "vector"
    if images:
        return "raster"
    if paths:
        return "vector"
    return "empty"


def render_page(data: bytes, page_index: int, zoom: float = 2.0, max_side: int = 4200) -> tuple[np.ndarray, float]:
    import pymupdf

    doc = _open(data)
    if not 0 <= page_index < doc.page_count:
        raise PdfError(f"page {page_index + 1} does not exist (document has {doc.page_count} pages)")
    page = doc[page_index]
    zoom = min(zoom, max_side / max(page.rect.width, page.rect.height))
    pix = page.get_pixmap(matrix=pymupdf.Matrix(zoom, zoom), alpha=False)
    img = np.frombuffer(pix.samples, np.uint8).reshape(pix.height, pix.width, pix.n)
    img = cv2.cvtColor(img, cv2.COLOR_RGB2BGR) if pix.n == 3 else cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
    doc.close()
    return img.copy(), zoom


@dataclass
class Word:
    text: str
    bbox: tuple[float, float, float, float]
    line_text: str = ""
    source: str = "text_layer"
    confidence: float | None = None

    @property
    def norm(self) -> str:
        return _norm(self.text)

    @property
    def center(self) -> tuple[float, float]:
        return ((self.bbox[0] + self.bbox[2]) / 2, (self.bbox[1] + self.bbox[3]) / 2)


@dataclass
class Rect:
    bbox: tuple[float, float, float, float]
    dashed: bool = False
    source: str = "vector"

    @property
    def w(self) -> float:
        return self.bbox[2] - self.bbox[0]

    @property
    def h(self) -> float:
        return self.bbox[3] - self.bbox[1]

    @property
    def area(self) -> float:
        return max(0.0, self.w) * max(0.0, self.h)

    def contains(self, b, tol: float = 1.0) -> bool:
        return b[0] >= self.bbox[0] - tol and b[1] >= self.bbox[1] - tol and b[2] <= self.bbox[2] + tol and b[3] <= self.bbox[3] + tol


@dataclass
class ParsedDrawing:
    page_index: int
    page_count: int
    width: float
    height: float
    kind: str
    words: list[Word]
    lines: list[dict]
    rects: list[Rect]
    render: np.ndarray
    render_scale: float
    warnings: list[dict] = field(default_factory=list)
    stats: dict = field(default_factory=dict)


def parse_drawing(data: bytes, page_index: int = 0, ocr=None) -> ParsedDrawing:
    doc = _open(data)
    if not 0 <= page_index < doc.page_count:
        raise PdfError(f"page {page_index + 1} does not exist (document has {doc.page_count} pages)")
    page = doc[page_index]
    W, H = float(page.rect.width), float(page.rect.height)
    warnings: list[dict] = []
    words: list[Word] = []
    lines: list[dict] = []
    td = page.get_text("dict")
    for block in td.get("blocks", []):
        for line in block.get("lines", []):
            text = "".join(sp.get("text", "") for sp in line.get("spans", [])).strip()
            if not text:
                continue
            size = max((sp.get("size", 0) for sp in line.get("spans", [])), default=0)
            lines.append({"text": text, "bbox": [round(v, 2) for v in line["bbox"]], "size": round(size, 2)})
    for x0, y0, x1, y1, w, *_ in page.get_text("words"):
        words.append(Word(w, (x0, y0, x1, y1)))
    for wd in words:
        for ln in lines:
            b = ln["bbox"]
            if b[0] - 0.5 <= wd.center[0] <= b[2] + 0.5 and b[1] - 0.5 <= wd.center[1] <= b[3] + 0.5:
                wd.line_text = ln["text"]
                break
    rects: list[Rect] = []
    try:
        drawings = page.get_drawings()
    except Exception as exc:
        drawings = []
        warnings.append({"code": "vector_extraction_failed", "message": f"Vector path extraction failed: {exc}"})
    for path in drawings:
        dashed = bool(path.get("dashes")) and path.get("dashes") not in ("[] 0", "[] 0.0")
        items = path.get("items", [])
        for it in items:
            if it[0] == "re":
                r = it[1]
                rects.append(Rect((r.x0, r.y0, r.x1, r.y1), dashed))
            elif it[0] == "qu":
                r = it[1].rect
                rects.append(Rect((r.x0, r.y0, r.x1, r.y1), dashed))
        if items and all(it[0] == "l" for it in items) and len(items) in (3, 4) and path.get("closePath", len(items) == 4):
            r = path["rect"]
            rects.append(Rect((r.x0, r.y0, r.x1, r.y1), dashed))
    rects = [r for r in rects if r.w > 2 and r.h > 2 and not (r.w > W * 0.97 and r.h > H * 0.97)]
    n_img = len(page.get_images(full=True))
    kind = classify_page(len(words), len(drawings), n_img)
    doc.close()
    render, scale = render_page(data, page_index, zoom=2.0)
    if kind in ("raster", "mixed") and len(words) < 5:
        if ocr is None:
            warnings.append({"code": "raster_no_ocr", "message": "Raster drawing and OCR is unavailable: no text could be extracted. Define zones manually."})
        else:
            hi, hs = render_page(data, page_index, zoom=300 / 72, max_side=6000)
            try:
                regions = ocr.read(hi, allowlist=None)
                for r in regions:
                    x0, y0, x1, y1 = r.box
                    words.append(Word(r.text, (x0 / hs, y0 / hs, x1 / hs, y1 / hs), r.text, "ocr", r.confidence))
                    lines.append({"text": r.text, "bbox": [x0 / hs, y0 / hs, x1 / hs, y1 / hs], "size": (y1 - y0) / hs, "source": "ocr", "confidence": r.confidence})
                warnings.append({"code": "raster_ocr", "message": f"Raster drawing: {len(regions)} text regions read by OCR at 300 DPI. Verify extracted identifiers."})
            except Exception as exc:
                warnings.append({"code": "raster_ocr_failed", "message": f"OCR of raster drawing failed: {exc}"})
            rects.extend(detect_rects_raster(hi, hs))
    if not words:
        warnings.append({"code": "no_text", "message": "No text could be extracted from the selected page."})
    stats = {"words": len(words), "lines": len(lines), "rects": len(rects), "vector_paths": len(drawings), "images": n_img}
    return ParsedDrawing(page_index, 0, W, H, kind, words, lines, rects, render, scale, warnings, stats)


def detect_rects_raster(img: np.ndarray, scale: float) -> list[Rect]:
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    _, th = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    contours, _ = cv2.findContours(th, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    out = []
    for c in contours:
        peri = cv2.arcLength(c, True)
        approx = cv2.approxPolyDP(c, 0.02 * peri, True)
        if len(approx) == 4 and cv2.isContourConvex(approx):
            x, y, w, h = cv2.boundingRect(approx)
            if w * h > 400:
                out.append(Rect((x / scale, y / scale, (x + w) / scale, (y + h) / scale), False, "raster_contour"))
    return out


# ---------------------------------------------------------------------------
# Zones and tag location
# ---------------------------------------------------------------------------

def extract_zones(pd: ParsedDrawing) -> list[dict]:
    zones: dict[str, dict] = {}
    for wd in pd.words:
        m = ZONE_RE.match(wd.norm)
        if not m:
            continue
        code = f"Z{m.group(1).upper()}"
        if code in zones:
            continue
        label_area = max(1.0, (wd.bbox[2] - wd.bbox[0]) * (wd.bbox[3] - wd.bbox[1]))
        enclosing = [r for r in pd.rects if r.contains(wd.bbox) and r.area > 20 * label_area]
        if not enclosing:
            continue
        enclosing.sort(key=lambda r: (not r.dashed, r.area))
        r = enclosing[0]
        name = wd.line_text
        rest = name.split(None, 1)
        name = rest[1] if len(rest) > 1 and _norm(rest[0]) == wd.norm else (name if name != wd.text else None)
        zones[code] = {"code": code, "name": name, "bbox": [round(v, 2) for v in r.bbox], "source": "drawing_frame", "dashed": r.dashed}
    return sorted(zones.values(), key=lambda z: (len(z["code"]), z["code"]))


def _is_label_like(rect: Rect, word_bbox) -> bool:
    th = max(1e-6, word_bbox[3] - word_bbox[1])
    tw = max(1e-6, word_bbox[2] - word_bbox[0])
    return rect.h <= 3.2 * th and rect.w <= max(5.0 * tw, tw + 6 * th)


def locate_identifier(pd: ParsedDrawing, ident: str, body_search: bool = True) -> dict:
    """Locate an identifier (device tag or ferrule text) in the drawing.

    Returns {found, match, label_bbox, body_bbox, occurrences, note}.
    """
    target = _norm(ident)
    occ = [w for w in pd.words if w.norm == target]
    if not occ:
        # multi-word identifiers or identifiers split by the text layer
        occ = [Word(ln["text"], tuple(ln["bbox"]), ln["text"]) for ln in pd.lines if _norm(ln["text"]) == target]
    if not occ:
        return {"found": False, "match": "not_found", "occurrences": 0}
    results = []
    for w in occ:
        enclosing = sorted([r for r in pd.rects if r.contains(w.bbox, tol=1.5) and not r.dashed], key=lambda r: r.area)
        if not enclosing:
            b = w.bbox
            pad = (b[3] - b[1])
            results.append({"match": "text_only", "label_bbox": list(b), "body_bbox": [b[0] - pad, b[1] - pad, b[2] + pad, b[3] + pad]})
            continue
        inner = enclosing[0]
        if _is_label_like(inner, w.bbox):
            body = _find_body(pd, inner) if body_search else None
            if body is not None:
                results.append({"match": "label_plate+body", "label_bbox": list(inner.bbox), "body_bbox": list(body.bbox)})
            else:
                results.append({"match": "label_only", "label_bbox": list(inner.bbox), "body_bbox": list(inner.bbox)})
        else:
            results.append({"match": "tag_in_body", "label_bbox": list(w.bbox), "body_bbox": list(inner.bbox)})
    rank = {"label_plate+body": 0, "tag_in_body": 1, "label_only": 2, "text_only": 3}
    results.sort(key=lambda r: rank[r["match"]])
    best = results[0]
    note = None
    if len(results) > 1:
        note = f"identifier appears {len(results)} times in the drawing; using the {best['match']} occurrence"
    return {"found": True, "occurrences": len(results), "note": note, **{k: [round(v, 2) for v in val] if isinstance(val, list) else val for k, val in best.items()}}


def _find_body(pd: ParsedDrawing, label: Rect) -> Rect | None:
    lh = label.h
    best = None
    best_gap = None
    for r in pd.rects:
        if r is label or r.area <= label.area * 1.5 or r.dashed:
            continue
        if r.contains(label.bbox):
            continue
        ov = min(r.bbox[2], label.bbox[2]) - max(r.bbox[0], label.bbox[0])
        if ov < 0.5 * min(r.w, label.w):
            continue
        gap_below = r.bbox[1] - label.bbox[3]
        gap_above = label.bbox[1] - r.bbox[3]
        gap = gap_below if gap_below >= -0.5 else (gap_above if gap_above >= -0.5 else None)
        if gap is None or gap > 3.5 * lh:
            continue
        if r.area > 200 * label.area:
            continue
        if best_gap is None or gap < best_gap:
            best, best_gap = r, gap
    return best


def derive_zones_from_components(located: dict[str, list[list[float]]], margin: float = 8.0) -> list[dict]:
    zones = []
    for code, boxes in sorted(located.items()):
        if not boxes:
            continue
        arr = np.array(boxes)
        zones.append({
            "code": code,
            "name": None,
            "bbox": [round(float(arr[:, 0].min() - margin), 2), round(float(arr[:, 1].min() - margin), 2), round(float(arr[:, 2].max() + margin), 2), round(float(arr[:, 3].max() + margin), 2)],
            "source": "derived_from_components",
        })
    return zones
