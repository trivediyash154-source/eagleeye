"""Annotation rendering for evidence images (OpenCV)."""
from __future__ import annotations

import cv2
import numpy as np

VERDICT_BGR = {"PASS": (110, 200, 40), "FAIL": (60, 60, 235), "UNCERTAIN": (30, 170, 245)}
CLASS_BGR = {
    "circuit_breaker": (255, 200, 60),
    "contactor": (240, 120, 200),
    "power_supply": (90, 220, 255),
    "terminal_block": (200, 200, 90),
    "wire_marker": (255, 255, 255),
    "device_label": (120, 255, 160),
    "earth_bar": (60, 200, 255),
}


def _thick(img: np.ndarray) -> int:
    return max(2, int(round(max(img.shape[:2]) / 900)))


def label(img: np.ndarray, text: str, x: int, y: int, color, scale: float | None = None) -> None:
    s = scale or max(0.5, max(img.shape[:2]) / 2600)
    th = max(1, int(round(s * 2)))
    (tw, tht), base = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, s, th)
    y = max(tht + 4, y)
    cv2.rectangle(img, (x, y - tht - 6), (x + tw + 8, y + base - 2), color, -1)
    lum = 0.114 * color[0] + 0.587 * color[1] + 0.299 * color[2]
    cv2.putText(img, text, (x + 4, y - 4), cv2.FONT_HERSHEY_SIMPLEX, s, (15, 15, 15) if lum > 140 else (250, 250, 250), th, cv2.LINE_AA)


def box(img: np.ndarray, b, color, text: str | None = None, dashed: bool = False, thickness: int | None = None) -> None:
    x0, y0, x1, y1 = [int(round(v)) for v in b]
    t = thickness or _thick(img)
    if dashed:
        for (a, c) in (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))):
            dist = int(np.hypot(c[0] - a[0], c[1] - a[1]))
            for i in range(0, dist, 18):
                p = (int(a[0] + (c[0] - a[0]) * i / max(1, dist)), int(a[1] + (c[1] - a[1]) * i / max(1, dist)))
                q = (int(a[0] + (c[0] - a[0]) * min(dist, i + 10) / max(1, dist)), int(a[1] + (c[1] - a[1]) * min(dist, i + 10) / max(1, dist)))
                cv2.line(img, p, q, color, t, cv2.LINE_AA)
    else:
        cv2.rectangle(img, (x0, y0), (x1, y1), color, t, cv2.LINE_AA)
    if text:
        label(img, text, x0, y0 - 2, color)


def poly(img: np.ndarray, pts, color, thickness: int | None = None, fill_alpha: float = 0.0) -> None:
    p = np.array(pts, np.int32).reshape(-1, 1, 2)
    if fill_alpha > 0:
        ov = img.copy()
        cv2.fillPoly(ov, [p], color)
        cv2.addWeighted(ov, fill_alpha, img, 1 - fill_alpha, 0, img)
    cv2.polylines(img, [p], True, color, thickness or _thick(img), cv2.LINE_AA)


def crop_with_padding(img: np.ndarray, b, pad_frac: float = 0.35, min_pad: int = 24) -> tuple[np.ndarray, list[int]]:
    h, w = img.shape[:2]
    x0, y0, x1, y1 = b
    pw = max(min_pad, (x1 - x0) * pad_frac)
    ph = max(min_pad, (y1 - y0) * pad_frac)
    cx0, cy0 = int(max(0, x0 - pw)), int(max(0, y0 - ph))
    cx1, cy1 = int(min(w, x1 + pw)), int(min(h, y1 + ph))
    return img[cy0:cy1, cx0:cx1].copy(), [cx0, cy0, cx1, cy1]
