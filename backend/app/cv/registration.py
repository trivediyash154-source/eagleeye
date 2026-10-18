"""Photo-to-drawing registration.

H maps drawing coordinates (PDF points) to ORIGINAL photo pixels: x_photo ~ H · x_drawing.

Three methods are attempted, each validated independently:

* ``features`` — SIFT (ORB fallback) keypoints on the rendered drawing and the photo, Lowe ratio
  test, RANSAC homography. Line drawings and photographs look very different, so this often
  fails on real data; failure is reported, never hidden.
* ``text_anchors`` — identifiers that appear exactly once in the drawing text layer and exactly
  once in the photo OCR results (e.g. device tags, ferrule numbers) give point correspondences,
  then RANSAC. This exploits the one modality both inputs share: printed identifiers.
* ``manual_anchors`` — four or more inspector-selected point pairs.

A homography is accepted only when inlier count, inlier ratio, spatial coverage, orientation,
convexity, scale plausibility and reprojection error all pass. A matrix returned by OpenCV is
never accepted on its own. The planar model ignores component depth (parallax), which is a
documented limitation for strongly oblique photographs.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import cv2
import numpy as np

from ..core.logging import get_logger
from ..core.util import jsonable

log = get_logger("cv.registration")


@dataclass
class RegistrationResult:
    status: str  # aligned | manual | insufficient | failed | unavailable
    method: str | None
    H: np.ndarray | None
    metrics: dict = field(default_factory=dict)
    checks: list[dict] = field(default_factory=list)
    reasons: list[str] = field(default_factory=list)
    attempts: list[dict] = field(default_factory=list)
    correspondences: list[dict] = field(default_factory=list)

    @property
    def usable(self) -> bool:
        return self.status in ("aligned", "manual") and self.H is not None

    def to_json(self) -> dict:
        return jsonable({
            "status": self.status,
            "method": self.method,
            "usable": self.usable,
            "homography": self.H.tolist() if self.H is not None else None,
            "metrics": self.metrics,
            "checks": self.checks,
            "reasons": self.reasons,
            "attempts": self.attempts,
            "correspondences": self.correspondences[:200],
            "convention": "H maps drawing PDF points (origin top-left) to original photo pixels",
        })


def project_points(H: np.ndarray, pts) -> np.ndarray:
    p = np.asarray(pts, np.float64).reshape(-1, 1, 2)
    return cv2.perspectiveTransform(p, H).reshape(-1, 2)


def project_bbox(H: np.ndarray, bbox) -> tuple[list[float], list[list[float]]]:
    x0, y0, x1, y1 = bbox
    quad = project_points(H, [[x0, y0], [x1, y0], [x1, y1], [x0, y1]])
    return [float(quad[:, 0].min()), float(quad[:, 1].min()), float(quad[:, 0].max()), float(quad[:, 1].max())], quad.tolist()


def _poly_area(q: np.ndarray) -> float:
    x, y = q[:, 0], q[:, 1]
    return 0.5 * abs(float(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1))))


def validate(H: np.ndarray | None, src: np.ndarray, dst: np.ndarray, inlier_mask: np.ndarray | None, drawing_size: tuple[float, float],
             photo_size: tuple[int, int], min_inliers: int, min_ratio: float, max_err_frac: float = 0.015) -> tuple[bool, list[dict], dict]:
    checks: list[dict] = []
    metrics: dict = {"correspondences": int(len(src))}
    if H is None or not np.all(np.isfinite(H)):
        checks.append({"name": "homography_estimated", "passed": False, "detail": "no homography could be estimated"})
        return False, checks, metrics
    pw, ph = photo_size
    diag = float(np.hypot(pw, ph))
    mask = inlier_mask.ravel().astype(bool) if inlier_mask is not None else np.ones(len(src), bool)
    n_in = int(mask.sum())
    ratio = n_in / max(1, len(src))
    metrics.update({"inliers": n_in, "inlier_ratio": round(ratio, 3)})
    checks.append({"name": "min_inliers", "passed": n_in >= min_inliers, "value": n_in, "threshold": min_inliers})
    checks.append({"name": "inlier_ratio", "passed": ratio >= min_ratio, "value": round(ratio, 3), "threshold": min_ratio})
    if n_in >= 4:
        proj = project_points(H, src[mask])
        err = np.linalg.norm(proj - dst[mask], axis=1)
        med = float(np.median(err))
        metrics["reprojection_error_median_px"] = round(med, 2)
        metrics["reprojection_error_p90_px"] = round(float(np.percentile(err, 90)), 2)
        checks.append({"name": "reprojection_error", "passed": med <= max_err_frac * diag, "value": round(med, 2), "threshold": round(max_err_frac * diag, 2), "unit": "px"})
        # spatial coverage of inliers over the photo (3x3 grid)
        cells = {(min(2, int(x / pw * 3)), min(2, int(y / ph * 3))) for x, y in dst[mask] if 0 <= x < pw and 0 <= y < ph}
        metrics["coverage_cells_3x3"] = len(cells)
        hull = cv2.convexHull(dst[mask].astype(np.float32))
        hull_frac = float(cv2.contourArea(hull)) / float(pw * ph)
        metrics["inlier_hull_area_fraction"] = round(hull_frac, 3)
        checks.append({"name": "spatial_coverage", "passed": len(cells) >= 3 and hull_frac >= 0.06, "value": {"cells": len(cells), "hull_fraction": round(hull_frac, 3)}, "threshold": {"cells": 3, "hull_fraction": 0.06}})
    dw, dh = drawing_size
    quad = project_points(H, [[0, 0], [dw, 0], [dw, dh], [0, dh]])
    det = float(np.linalg.det(H[:2, :2]))
    metrics["linear_determinant"] = round(det, 6)
    checks.append({"name": "orientation_preserved", "passed": det > 0, "value": round(det, 6), "detail": "a negative determinant means a mirrored mapping"})
    convex = bool(cv2.isContourConvex(quad.astype(np.float32).reshape(-1, 1, 2)))
    checks.append({"name": "projected_page_convex", "passed": convex})
    area_ratio = _poly_area(quad) / float(pw * ph)
    metrics["projected_page_area_ratio"] = round(area_ratio, 3)
    checks.append({"name": "plausible_scale", "passed": 0.08 <= area_ratio <= 25, "value": round(area_ratio, 3), "threshold": [0.08, 25]})
    sides = [np.linalg.norm(quad[i] - quad[(i + 1) % 4]) for i in range(4)]
    opp = max(sides[0] / max(1e-6, sides[2]), sides[2] / max(1e-6, sides[0]), sides[1] / max(1e-6, sides[3]), sides[3] / max(1e-6, sides[1]))
    metrics["opposite_side_ratio_max"] = round(float(opp), 3)
    checks.append({"name": "limited_perspective", "passed": opp <= 2.5, "value": round(float(opp), 3), "threshold": 2.5})
    ok = all(c["passed"] for c in checks)
    return ok, checks, metrics


def register_features(drawing_img: np.ndarray, drawing_scale: float, photo: np.ndarray, drawing_size, method: str = "SIFT", work_side: int = 1600) -> dict:
    """Feature-based attempt. drawing_img is the page render (render px = pt * drawing_scale)."""
    g1 = cv2.cvtColor(drawing_img, cv2.COLOR_BGR2GRAY)
    g2 = cv2.cvtColor(photo, cv2.COLOR_BGR2GRAY)
    s1 = work_side / max(g1.shape)
    s2 = work_side / max(g2.shape)
    g1 = cv2.resize(g1, None, fx=s1, fy=s1, interpolation=cv2.INTER_AREA)
    g2 = cv2.resize(g2, None, fx=s2, fy=s2, interpolation=cv2.INTER_AREA)
    g2 = cv2.createCLAHE(2.0, (8, 8)).apply(g2)
    use = method
    if method == "SIFT" and hasattr(cv2, "SIFT_create"):
        det = cv2.SIFT_create(nfeatures=6000)
        norm = cv2.NORM_L2
    else:
        use = "ORB"
        det = cv2.ORB_create(nfeatures=6000)
        norm = cv2.NORM_HAMMING
    k1, d1 = det.detectAndCompute(g1, None)
    k2, d2 = det.detectAndCompute(g2, None)
    info = {"method": f"features:{use}", "keypoints_drawing": len(k1), "keypoints_photo": len(k2)}
    if d1 is None or d2 is None or len(k1) < 8 or len(k2) < 8:
        info["error"] = "too few keypoints"
        return {**info, "H": None, "src": np.zeros((0, 2)), "dst": np.zeros((0, 2)), "mask": None}
    matcher = cv2.BFMatcher(norm)
    knn = matcher.knnMatch(d1, d2, k=2)
    good = [m for m, *rest in knn if rest and m.distance < 0.75 * rest[0].distance]
    info["ratio_test_matches"] = len(good)
    if len(good) < 8:
        info["error"] = "fewer than 8 matches survived the Lowe ratio test (0.75)"
        return {**info, "H": None, "src": np.zeros((0, 2)), "dst": np.zeros((0, 2)), "mask": None}
    src = np.array([k1[m.queryIdx].pt for m in good], np.float64) / s1 / drawing_scale  # -> drawing points
    dst = np.array([k2[m.trainIdx].pt for m in good], np.float64) / s2  # -> photo px
    H, mask = cv2.findHomography(src, dst, cv2.RANSAC, ransacReprojThreshold=0.006 * float(np.hypot(*photo.shape[:2])))
    return {**info, "H": H, "src": src, "dst": dst, "mask": mask}


def text_anchor_pairs(drawing_words: list[tuple[str, tuple]], photo_obs: list[tuple[str, tuple, float]], min_conf: float = 0.5, min_len: int = 2) -> list[dict]:
    from collections import Counter

    dcount = Counter(t for t, _ in drawing_words)
    pcount = Counter(t for t, _, c in photo_obs if c >= min_conf)
    pairs = []
    for t, db in drawing_words:
        if dcount[t] != 1 or pcount.get(t, 0) != 1 or len(t) < min_len or t.isdigit():
            continue
        pb, pc = next((b, c) for tt, b, c in photo_obs if tt == t and c >= min_conf)
        pairs.append({
            "text": t,
            "drawing": [(db[0] + db[2]) / 2, (db[1] + db[3]) / 2],
            "photo": [(pb[0] + pb[2]) / 2, (pb[1] + pb[3]) / 2],
            "ocr_confidence": round(pc, 3),
        })
    return pairs


def register_text_anchors(pairs: list[dict], photo_shape) -> dict:
    info = {"method": "text_anchors", "candidate_pairs": len(pairs)}
    if len(pairs) < 4:
        info["error"] = f"only {len(pairs)} unique identifiers shared by drawing and photo OCR (need ≥ 4)"
        return {**info, "H": None, "src": np.zeros((0, 2)), "dst": np.zeros((0, 2)), "mask": None}
    src = np.array([p["drawing"] for p in pairs], np.float64)
    dst = np.array([p["photo"] for p in pairs], np.float64)
    thr = 0.012 * float(np.hypot(*photo_shape[:2]))
    H, mask = cv2.findHomography(src, dst, cv2.RANSAC, ransacReprojThreshold=thr, maxIters=5000, confidence=0.999)
    if H is not None and mask is not None and mask.sum() >= 4:
        # refine on inliers with least squares
        m = mask.ravel().astype(bool)
        H2, _ = cv2.findHomography(src[m], dst[m], 0)
        if H2 is not None:
            H = H2
    return {**info, "H": H, "src": src, "dst": dst, "mask": mask}


def register_manual(anchors: list[dict], drawing_size, photo_shape) -> RegistrationResult:
    src = np.array([a["drawing"] for a in anchors], np.float64)
    dst = np.array([a["photo"] for a in anchors], np.float64)
    if len(anchors) < 4:
        return RegistrationResult("failed", "manual_anchors", None, reasons=["at least 4 anchor pairs are required"])
    H, mask = cv2.findHomography(src, dst, 0 if len(anchors) == 4 else cv2.RANSAC, 0.02 * float(np.hypot(*photo_shape[:2])))
    ok, checks, metrics = validate(H, src, dst, mask, drawing_size, (photo_shape[1], photo_shape[0]), 4, 0.75, max_err_frac=0.03)
    # manual anchors are deliberately placed: coverage check uses anchors themselves
    status = "manual" if ok else "insufficient"
    reasons = [] if ok else [f"check failed: {c['name']}" for c in checks if not c["passed"]]
    corr = [{"text": a.get("label", f"A{i + 1}"), "drawing": a["drawing"], "photo": a["photo"], "inlier": True} for i, a in enumerate(anchors)]
    return RegistrationResult(status, "manual_anchors", H if H is not None else None, metrics, checks, reasons, [{"method": "manual_anchors", "accepted": ok, **metrics}], corr)


def register(drawing_img: np.ndarray | None, drawing_scale: float, drawing_size, photo: np.ndarray, anchor_pairs: list[dict] | None,
             manual_anchors: list[dict] | None = None) -> RegistrationResult:
    ph, pw = photo.shape[:2]
    if manual_anchors:
        return register_manual(manual_anchors, drawing_size, photo.shape)
    if drawing_img is None:
        return RegistrationResult("unavailable", None, None, reasons=["no GA drawing was supplied"])
    attempts = []
    accepted = []
    tried = []
    try:
        f = register_features(drawing_img, drawing_scale, photo, drawing_size, "SIFT")
        tried.append((f, 15, 0.25))
    except Exception as exc:
        attempts.append({"method": "features", "accepted": False, "error": f"{type(exc).__name__}: {exc}"})
    if anchor_pairs is not None:
        tried.append((register_text_anchors(anchor_pairs, photo.shape), 6, 0.5))
    for res, min_in, min_ratio in tried:
        H = res.get("H")
        ok, checks, metrics = validate(H, res["src"], res["dst"], res.get("mask"), drawing_size, (pw, ph), min_in, min_ratio)
        att = {k: v for k, v in res.items() if k not in ("H", "src", "dst", "mask")}
        att.update({"accepted": ok, "metrics": metrics, "checks": checks})
        attempts.append(att)
        if ok:
            accepted.append((res, metrics, checks))
    if accepted:
        accepted.sort(key=lambda a: a[1].get("reprojection_error_median_px", 1e9))
        res, metrics, checks = accepted[0]
        mask = res.get("mask")
        m = mask.ravel().astype(bool) if mask is not None else np.ones(len(res["src"]), bool)
        corr = []
        if res["method"] == "text_anchors":
            for p, inl in zip(anchor_pairs or [], m):
                corr.append({**p, "inlier": bool(inl)})
        else:
            for s_, d_, inl in list(zip(res["src"], res["dst"], m))[:200]:
                corr.append({"drawing": s_.tolist(), "photo": d_.tolist(), "inlier": bool(inl)})
        return RegistrationResult("aligned", res["method"], res["H"], metrics, checks, [], attempts, corr)
    reasons = []
    best_partial = None
    for att in attempts:
        if att.get("error"):
            reasons.append(f"{att['method']}: {att['error']}")
        else:
            failed = [c["name"] for c in att.get("checks", []) if not c["passed"]]
            reasons.append(f"{att['method']}: rejected ({', '.join(failed)})")
            best_partial = best_partial or att
    status = "insufficient" if best_partial else "failed"
    return RegistrationResult(status, None, None, best_partial["metrics"] if best_partial else {}, best_partial["checks"] if best_partial else [], reasons, attempts)
