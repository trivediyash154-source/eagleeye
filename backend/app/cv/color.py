"""Experimental wire-colour classification.

Pixels in a narrow strip along the expected wire path are classified to the nearest named
colour in CIELAB. A result is only considered defensible when lighting is adequate and one
colour clearly dominates; otherwise the caller must report UNCERTAIN.
"""
from __future__ import annotations

import cv2
import numpy as np

# reference sRGB values for common IEC 60445 wire colours
REFERENCE_RGB = {
    "brown": (122, 74, 42),
    "blue": (40, 84, 196),
    "dark_blue": (26, 44, 120),
    "black": (30, 30, 32),
    "grey": (128, 130, 134),
    "red": (196, 40, 38),
    "white": (232, 232, 228),
    "orange": (226, 122, 32),
    "yellow": (230, 210, 40),
    "green": (70, 160, 60),
}
SYNONYMS = {
    "bk": "black", "blk": "black", "schwarz": "black",
    "bn": "brown", "brn": "brown", "braun": "brown",
    "bu": "blue", "blu": "blue", "lightblue": "blue", "light blue": "blue", "blau": "blue",
    "gy": "grey", "gray": "grey", "gr": "grey",
    "rd": "red", "wh": "white", "wt": "white", "og": "orange", "ye": "yellow", "gn": "green",
    "darkblue": "dark_blue", "dark blue": "dark_blue", "db": "dark_blue",
    "gnye": "green_yellow", "gn/ye": "green_yellow", "green/yellow": "green_yellow", "green-yellow": "green_yellow", "green_yellow": "green_yellow", "pe": "green_yellow",
}


def canonical_color(name: str | None) -> str | None:
    if not name:
        return None
    k = name.strip().lower()
    if k in REFERENCE_RGB or k == "green_yellow":
        return k
    return SYNONYMS.get(k, SYNONYMS.get(k.replace(" ", ""), k.replace(" ", "_")))


def _lab(rgb) -> np.ndarray:
    arr = np.uint8([[list(rgb)]])
    return cv2.cvtColor(arr, cv2.COLOR_RGB2LAB)[0, 0].astype(np.float32)


_REF_LAB = {k: _lab(v) for k, v in REFERENCE_RGB.items()}


def classify_strip(region_bgr: np.ndarray) -> dict:
    """Find the wire column in a region and classify its colour."""
    if region_bgr is None or region_bgr.size == 0 or region_bgr.shape[0] < 6 or region_bgr.shape[1] < 6:
        return {"ok": False, "reason": "region too small"}
    lab = cv2.cvtColor(region_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    h, w = lab.shape[:2]
    border = np.concatenate([lab[:, : max(1, w // 8)].reshape(-1, 3), lab[:, -max(1, w // 8):].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    diff = np.linalg.norm(lab - bg[None, None, :], axis=2).mean(axis=0)
    band = max(2, w // 10)
    smooth = np.convolve(diff, np.ones(band) / band, mode="same")
    cx = int(np.argmax(smooth))
    x0, x1 = max(0, cx - band // 2), min(w, cx + band // 2 + 1)
    px = lab[:, x0:x1].reshape(-1, 3)
    names = list(_REF_LAB)
    refs = np.stack([_REF_LAB[n] for n in names])
    d = np.linalg.norm(px[:, None, :] - refs[None, :, :], axis=2)
    idx = d.argmin(axis=1)
    counts = np.bincount(idx, minlength=len(names)) / max(1, len(idx))
    dist = {names[i]: round(float(c), 3) for i, c in enumerate(counts) if c > 0.02}
    order = np.argsort(counts)[::-1]
    top = names[order[0]]
    frac = float(counts[order[0]])
    # green/yellow stripes: two colours each substantial
    if {names[order[0]], names[order[1]]} == {"green", "yellow"} and counts[order[1]] > 0.2:
        top, frac = "green_yellow", float(counts[order[0]] + counts[order[1]])
    lightness = float(px[:, 0].mean()) * 100 / 255
    contrast_vs_bg = float(smooth[cx])
    return {
        "ok": True,
        "color": top,
        "fraction": round(frac, 3),
        "distribution": dist,
        "lightness": round(lightness, 1),
        "contrast_vs_background": round(contrast_vs_bg, 1),
        "column_px": [x0, x1],
    }
