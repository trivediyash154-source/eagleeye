import io

import cv2
import numpy as np
import pytest
from PIL import Image

from app.cv.detector import make_tiles, nms
from app.cv.preprocess import ImageDecodeError, assess_quality, decode_image, prepare
from app.cv.registration import register_manual, register_text_anchors, validate
from app.storage.local import LocalStorage, StorageError


def _jpeg(arr, exif_orientation=None) -> bytes:
    im = Image.fromarray(arr)
    buf = io.BytesIO()
    if exif_orientation:
        ex = Image.Exif()
        ex[0x0112] = exif_orientation
        im.save(buf, format="JPEG", exif=ex)
    else:
        im.save(buf, format="JPEG")
    return buf.getvalue()


def test_decode_rejects_non_images():
    with pytest.raises(ImageDecodeError):
        decode_image(b"%PDF-1.4 not an image")


def test_exif_orientation_applied():
    arr = np.zeros((40, 80, 3), np.uint8)
    d = decode_image(_jpeg(arr, exif_orientation=6))  # rotate 90°
    assert d.exif_orientation == 6
    assert d.bgr.shape[:2] == (80, 40)


def test_quality_flags_dark_and_blurry():
    dark = np.full((900, 1200, 3), 12, np.uint8)
    q = assess_quality(dark)
    codes = {w["code"] for w in q["warnings"]}
    assert "too_dark" in codes and q["rating"] == "poor"


def test_coordinate_roundtrip_with_resize_and_deskew(monkeypatch):
    from app.core import config

    monkeypatch.setattr(config.get_settings(), "max_processing_side", 500)
    img = np.full((800, 1000, 3), 200, np.uint8)
    cv2.line(img, (50, 300), (950, 330), (0, 0, 0), 4)
    cv2.line(img, (50, 500), (950, 530), (0, 0, 0), 4)
    cv2.line(img, (50, 700), (950, 730), (0, 0, 0), 4)
    pp = prepare(img, clahe=True, deskew=True)
    pts = np.array([[100.0, 100.0], [900.0, 700.0]])
    back = pp.to_original(pp.to_processed(pts))
    assert np.allclose(back, pts, atol=1e-6)
    assert pp.scale == pytest.approx(0.5)


def test_tiles_cover_image_and_nms():
    tiles = make_tiles(2500, 1800, 1024, 0.2)
    assert tiles and max(t[2] for t in tiles) == 2500 and max(t[3] for t in tiles) == 1800
    boxes = np.array([[0, 0, 10, 10], [1, 1, 10, 10], [50, 50, 60, 60]], float)
    keep = nms(boxes, np.array([0.9, 0.8, 0.7]), 0.5)
    assert sorted(keep) == [0, 2]


def _anchor_pairs(H, n=8):
    rng = np.random.default_rng(1)
    pairs = []
    for i in range(n):
        d = rng.uniform([50, 50], [1000, 700])
        p = cv2.perspectiveTransform(d.reshape(1, 1, 2), H).reshape(2)
        pairs.append({"text": f"T{i}", "drawing": d.tolist(), "photo": p.tolist(), "ocr_confidence": 0.9})
    return pairs


def test_text_anchor_registration_recovers_homography():
    H = np.array([[2.1, 0.05, 30], [0.02, 2.0, 40], [1e-5, 2e-5, 1]])
    pairs = _anchor_pairs(H)
    res = register_text_anchors(pairs, (1800, 2400, 3))
    ok, checks, metrics = validate(res["H"], res["src"], res["dst"], res["mask"], (1190, 842), (2400, 1800), 6, 0.5)
    assert ok, checks
    assert metrics["reprojection_error_median_px"] < 1.0


def test_too_few_anchors_rejected_and_mirror_rejected():
    res = register_text_anchors(_anchor_pairs(np.eye(3), 3), (1800, 2400, 3))
    assert res["H"] is None
    mirror = np.array([[-2.0, 0, 2400], [0, 2.0, 0], [0, 0, 1]])
    pairs = _anchor_pairs(mirror)
    src = np.array([p["drawing"] for p in pairs])
    dst = np.array([p["photo"] for p in pairs])
    ok, checks, _ = validate(mirror, src, dst, None, (1190, 842), (2400, 1800), 6, 0.5)
    assert not ok and not next(c for c in checks if c["name"] == "orientation_preserved")["passed"]


def test_manual_anchors():
    H = np.array([[2.0, 0, 10], [0, 2.0, 20], [0, 0, 1]])
    pairs = _anchor_pairs(H, 4)
    r = register_manual([{"drawing": p["drawing"], "photo": p["photo"]} for p in pairs], (1190, 842), (1800, 2400, 3))
    assert r.status == "manual" and r.usable


def test_storage_rejects_traversal(tmp_path):
    st = LocalStorage(tmp_path)
    for bad in ("../etc/passwd", "/abs/key.jpg", "a/../../b.jpg", "a\\b.jpg"):
        with pytest.raises(StorageError):
            st.path_for(bad)
    key = st.make_key("inspections", "x", ext="jpg")
    sha, n = st.put_bytes(key, b"abc")
    assert st.read_bytes(key) == b"abc" and n == 3 and len(sha) == 64
