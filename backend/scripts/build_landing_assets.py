"""Build the illustrative landing-page images from the bundled SYNTHETIC fixtures.

Usage: python scripts/build_landing_assets.py
Writes frontend/assets/landing/{ga_full.png, ga_zone_z4.png, photo_zone_z4.jpg, photo_full.jpg, ferrule_x12_4.png}.
These are illustrations derived from synthetic data and are labelled as such in the UI.
"""
from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.demo.synth_cabinet import demo_layout, render_photo  # noqa: E402
from app.drawing.pdf_parser import render_page  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "frontend" / "assets" / "landing"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    pdf = (ROOT / "data" / "demo" / "CAB-07_GA_drawing_SYNTHETIC.pdf").read_bytes()
    ga, zoom = render_page(pdf, 0, zoom=2.0)
    inv = 255 - ga  # light lines on dark for the UI
    tint = np.zeros_like(inv)
    tint[..., 0] = (inv[..., 0] * 1.0).astype(np.uint8)
    tint[..., 1] = (inv[..., 1] * 0.86).astype(np.uint8)
    tint[..., 2] = (inv[..., 2] * 0.55).astype(np.uint8)
    dark = cv2.addWeighted(np.full_like(ga, (22, 14, 7)), 1.0, tint, 0.95, 0)
    cv2.imwrite(str(OUT / "ga_full.png"), cv2.resize(dark, (1400, int(1400 * dark.shape[0] / dark.shape[1])), interpolation=cv2.INTER_AREA))
    # Z4 terminal-strip zone (mm layout -> pt via the generator's mapping: scale and origin from render_ga_pdf)
    lay = demo_layout("v1")
    scale = min((1190.55 - 72 - 40) / lay.width, (841.89 - 72 - 120) / lay.height)
    ox, oy = 56.0, 56.0
    z = next(z for z in lay.zones if z.code == "Z4")
    x0, y0 = int((ox + z.x * scale) * zoom), int((oy + z.y * scale) * zoom)
    x1, y1 = int((ox + (z.x + z.w) * scale) * zoom), int((oy + (z.y + z.h) * scale) * zoom)
    cv2.imwrite(str(OUT / "ga_zone_z4.png"), dark[max(0, y0 - 10):y1 + 10, max(0, x0 - 10):x1 + 10])
    img, boxes, H = render_photo(lay, seed=7, ppm=5.0, out_size=(4000, 3000), jitter=0.035)
    corners = np.array([[[z.x * 5.0, z.y * 5.0]], [[(z.x + z.w) * 5.0, z.y * 5.0]], [[(z.x + z.w) * 5.0, (z.y + z.h) * 5.0]], [[z.x * 5.0, (z.y + z.h) * 5.0]]], np.float32)
    q = cv2.perspectiveTransform(corners, H).reshape(-1, 2)
    px0, py0 = q.min(axis=0).astype(int)
    px1, py1 = q.max(axis=0).astype(int)
    cv2.imwrite(str(OUT / "photo_zone_z4.jpg"), img[max(0, py0 - 20):py1 + 20, max(0, px0 - 20):px1 + 20], [cv2.IMWRITE_JPEG_QUALITY, 88])
    cv2.imwrite(str(OUT / "photo_full.jpg"), cv2.resize(img, (1600, 1200), interpolation=cv2.INTER_AREA), [cv2.IMWRITE_JPEG_QUALITY, 86])
    fb = next(b for b in boxes if b[5] == "X12-8B")
    _, bx0, by0, bx1, by1, _ = fb
    pad = 70
    crop = img[int(by0) - pad:int(by1) + pad, int(bx0) - pad:int(bx1) + pad].copy()
    cv2.rectangle(crop, (pad, pad), (pad + int(bx1 - bx0), pad + int(by1 - by0)), (68, 68, 239), 3, cv2.LINE_AA)
    crop = cv2.resize(crop, None, fx=2.2, fy=2.2, interpolation=cv2.INTER_CUBIC)
    cv2.imwrite(str(OUT / "ferrule_x12_4.png"), crop)
    print("landing assets written to", OUT)


if __name__ == "__main__":
    main()
