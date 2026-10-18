"""Image ingestion, quality assessment and preprocessing.

Coordinate convention: the *original frame* is the uploaded image after EXIF orientation
correction. Every derivative records the transform back to that frame, and all persisted
coordinates (detections, OCR boxes, findings) are in original-frame pixels.
"""
from __future__ import annotations

import io
import math
from dataclasses import dataclass, field

import cv2
import numpy as np
from PIL import Image, ImageOps, UnidentifiedImageError

from ..core.config import get_settings

ALLOWED_IMAGE_FORMATS = {"JPEG": "image/jpeg", "PNG": "image/png"}


class ImageDecodeError(ValueError):
    pass


@dataclass
class DecodedImage:
    bgr: np.ndarray
    format: str
    exif_orientation: int
    original_size: tuple[int, int]  # as stored in the file (before EXIF rotation)


def decode_image(data: bytes) -> DecodedImage:
    settings = get_settings()
    Image.MAX_IMAGE_PIXELS = settings.max_image_pixels
    try:
        with Image.open(io.BytesIO(data)) as probe:
            probe.verify()
        im = Image.open(io.BytesIO(data))
        fmt = im.format or ""
        if fmt not in ALLOWED_IMAGE_FORMATS:
            raise ImageDecodeError(f"unsupported image format {fmt or 'unknown'}; JPEG or PNG required")
        raw_size = im.size
        orientation = 1
        try:
            orientation = int(im.getexif().get(0x0112, 1) or 1)
        except Exception:
            orientation = 1
        im = ImageOps.exif_transpose(im)
        im = im.convert("RGB")
        arr = cv2.cvtColor(np.asarray(im), cv2.COLOR_RGB2BGR)
    except Image.DecompressionBombError as exc:
        raise ImageDecodeError(f"image exceeds the configured pixel limit: {exc}") from exc
    except (UnidentifiedImageError, OSError, SyntaxError) as exc:
        raise ImageDecodeError(f"file is not a readable image: {exc}") from exc
    return DecodedImage(bgr=arr, format=fmt, exif_orientation=orientation, original_size=raw_size)


def assess_quality(bgr: np.ndarray) -> dict:
    """Image-quality diagnostics. Produces warnings; never rejects an image by itself."""
    h, w = bgr.shape[:2]
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    s = 1000.0 / max(h, w)
    g = cv2.resize(gray, (max(1, int(w * s)), max(1, int(h * s))), interpolation=cv2.INTER_AREA) if s < 1 else gray
    sharpness = float(cv2.Laplacian(g, cv2.CV_64F).var())
    brightness = float(gray.mean())
    contrast = float(gray.std())
    clipped_hi = float((gray >= 250).mean())
    clipped_lo = float((gray <= 5).mean())
    warnings: list[dict] = []
    if min(h, w) < 800:
        warnings.append({"code": "low_resolution", "message": f"Image is {w}×{h}px; small labels and ferrules may be unreadable (≥ 1600px on the short side recommended)."})
    if sharpness < 25:
        warnings.append({"code": "very_blurry", "message": f"Laplacian variance {sharpness:.0f} indicates strong blur; OCR results are likely unreliable."})
    elif sharpness < 60:
        warnings.append({"code": "blurry", "message": f"Laplacian variance {sharpness:.0f} suggests some blur."})
    if brightness < 55:
        warnings.append({"code": "too_dark", "message": f"Mean brightness {brightness:.0f}/255 — image is dark."})
    elif brightness > 215:
        warnings.append({"code": "overexposed", "message": f"Mean brightness {brightness:.0f}/255 — image is very bright."})
    if contrast < 28:
        warnings.append({"code": "low_contrast", "message": f"Grey-level std {contrast:.0f} — low contrast."})
    if clipped_hi > 0.08:
        warnings.append({"code": "clipped_highlights", "message": f"{clipped_hi * 100:.0f}% of pixels are saturated (glare)."})
    severe = {"very_blurry", "too_dark"}
    rating = "poor" if any(x["code"] in severe for x in warnings) else ("acceptable" if warnings else "good")
    return {
        "width": w,
        "height": h,
        "megapixels": round(w * h / 1e6, 2),
        "sharpness_laplacian_var": round(sharpness, 1),
        "brightness_mean": round(brightness, 1),
        "contrast_std": round(contrast, 1),
        "clipped_highlights_ratio": round(clipped_hi, 4),
        "clipped_shadows_ratio": round(clipped_lo, 4),
        "rating": rating,
        "warnings": warnings,
        "method": "Laplacian variance at 1000px long side; grey-level mean/std; saturation ratios",
    }


@dataclass
class PreparedImage:
    original: np.ndarray
    processed: np.ndarray
    scale: float  # processed = affine(original * scale)
    affine: np.ndarray  # 2x3 mapping scaled-original -> processed (deskew); identity if none
    transforms: list[dict] = field(default_factory=list)

    def to_original(self, pts: np.ndarray) -> np.ndarray:
        """Map Nx2 processed-image points back to original-frame pixels."""
        pts = np.asarray(pts, np.float64).reshape(-1, 2)
        A = np.vstack([self.affine, [0, 0, 1]])
        inv = np.linalg.inv(A)
        hom = np.hstack([pts, np.ones((len(pts), 1))]) @ inv.T
        return hom[:, :2] / self.scale

    def to_processed(self, pts: np.ndarray) -> np.ndarray:
        pts = np.asarray(pts, np.float64).reshape(-1, 2) * self.scale
        hom = np.hstack([pts, np.ones((len(pts), 1))]) @ np.vstack([self.affine, [0, 0, 1]]).T
        return hom[:, :2]

    def box_to_original(self, box: tuple[float, float, float, float]) -> list[float]:
        x0, y0, x1, y1 = box
        p = self.to_original(np.array([[x0, y0], [x1, y0], [x1, y1], [x0, y1]]))
        h, w = self.original.shape[:2]
        return [
            float(np.clip(p[:, 0].min(), 0, w)),
            float(np.clip(p[:, 1].min(), 0, h)),
            float(np.clip(p[:, 0].max(), 0, w)),
            float(np.clip(p[:, 1].max(), 0, h)),
        ]


def estimate_skew_degrees(gray: np.ndarray) -> float | None:
    edges = cv2.Canny(gray, 60, 160)
    h, w = gray.shape[:2]
    lines = cv2.HoughLinesP(edges, 1, np.pi / 720, threshold=200, minLineLength=int(w * 0.25), maxLineGap=12)
    if lines is None:
        return None
    angles = []
    for x1, y1, x2, y2 in lines[:, 0, :]:
        a = math.degrees(math.atan2(y2 - y1, x2 - x1))
        if abs(a) < 12:
            angles.append(a)
    if len(angles) < 3:
        return None
    return float(np.median(angles))


def prepare(original: np.ndarray, clahe: bool = True, denoise: bool = False, deskew: bool = False) -> PreparedImage:
    settings = get_settings()
    h, w = original.shape[:2]
    transforms: list[dict] = [{"op": "exif_orientation", "note": "applied at decode; defines the original frame"}]
    scale = 1.0
    img = original
    if max(h, w) > settings.max_processing_side:
        scale = settings.max_processing_side / max(h, w)
        img = cv2.resize(original, (int(round(w * scale)), int(round(h * scale))), interpolation=cv2.INTER_AREA)
        transforms.append({"op": "resize", "scale": round(scale, 5)})
    affine = np.array([[1, 0, 0], [0, 1, 0]], np.float64)
    if deskew:
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        ang = estimate_skew_degrees(gray)
        if ang is not None and 0.3 <= abs(ang) <= 8:
            ih, iw = img.shape[:2]
            affine = cv2.getRotationMatrix2D((iw / 2, ih / 2), ang, 1.0)
            img = cv2.warpAffine(img, affine, (iw, ih), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
            transforms.append({"op": "deskew", "angle_deg": round(ang, 3)})
        else:
            transforms.append({"op": "deskew", "skipped": True, "reason": "no reliable dominant angle in [0.3°, 8°]" if ang is None or abs(ang) > 8 else f"angle {ang:.2f}° below 0.3°"})
    if denoise:
        img = cv2.fastNlMeansDenoisingColored(img, None, 5, 5, 7, 21)
        transforms.append({"op": "denoise", "method": "fastNlMeansDenoisingColored h=5"})
    if clahe:
        lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
        l, a, b = cv2.split(lab)
        l = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8)).apply(l)
        img = cv2.cvtColor(cv2.merge([l, a, b]), cv2.COLOR_LAB2BGR)
        transforms.append({"op": "clahe", "clip_limit": 2.0, "tile_grid": [8, 8], "channel": "L (LAB)"})
    return PreparedImage(original=original, processed=img, scale=scale, affine=affine, transforms=transforms)


def encode_png(img: np.ndarray) -> bytes:
    ok, enc = cv2.imencode(".png", img)
    if not ok:
        raise RuntimeError("PNG encoding failed")
    return enc.tobytes()


def encode_jpeg(img: np.ndarray, quality: int = 90) -> bytes:
    ok, enc = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, quality])
    if not ok:
        raise RuntimeError("JPEG encoding failed")
    return enc.tobytes()


def thumbnail(img: np.ndarray, max_side: int = 360) -> np.ndarray:
    h, w = img.shape[:2]
    s = max_side / max(h, w)
    if s >= 1:
        return img
    return cv2.resize(img, (max(1, int(w * s)), max(1, int(h * s))), interpolation=cv2.INTER_AREA)
