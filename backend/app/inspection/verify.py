"""Deterministic verification engine.

Inputs are in-memory observations (detections, OCR observations), the expected records located
in the drawing, and the registration. Output is a list of finding drafts. The engine is pure
apart from an optional ``ocr_at`` callback for targeted OCR at an expected position, so it can
be unit-tested without a database or models.

Key principles:
  * PASS requires positive evidence; FAIL requires reliable contrary evidence; anything else
    is UNCERTAIN with machine-readable review reasons.
  * A failed registration never becomes "component missing".
  * Unreadable text never becomes a mismatch.
  * Confidence sources are kept separate; no combined score is fabricated.
"""
from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field

import numpy as np

from ..cv.color import canonical_color, classify_strip
from ..cv.registration import project_bbox
from ..ocr.normalize import normalize
from .matching import decide_identifier

LABEL_CLASSES = {"device_label", "wire_marker"}


@dataclass
class ObsDet:
    id: str
    cls: str
    conf: float
    box: tuple[float, float, float, float]
    above: bool


@dataclass
class ObsText:
    id: str
    raw: str
    norm: str
    conf: float
    box: tuple[float, float, float, float]
    region: str = "full"
    variant: str = "full"

    @property
    def center(self) -> tuple[float, float]:
        return ((self.box[0] + self.box[2]) / 2, (self.box[1] + self.box[3]) / 2)


@dataclass
class ExpComp:
    id: str
    tag: str
    zone: str | None
    cls: str | None
    cls_source: str
    label: str | None
    qty: int
    body_pt: list | None
    label_pt: list | None
    match: str | None


@dataclass
class ExpIdent:
    id: str
    kind: str
    value: str | None
    terminal_ref: str | None
    wire_color: str | None
    component_tag: str | None
    zone: str | None
    marker_pt: list | None
    terminal_pt: list | None
    match: str | None


@dataclass
class VerifyContext:
    H: np.ndarray | None
    registration: dict
    image: np.ndarray  # original-frame BGR
    quality_rating: str
    supported_classes: set[str]
    detector_kind: str
    detector_available: bool
    detector_conf: float
    ocr_available: bool
    zones_pt: dict[str, list]
    checks: set[str]
    policies: dict = field(default_factory=dict)
    ocr_at: Callable[[list[float], str], ObsText | None] | None = None


def _iou(a, b) -> float:
    x0, y0 = max(a[0], b[0]), max(a[1], b[1])
    x1, y1 = min(a[2], b[2]), min(a[3], b[3])
    inter = max(0.0, x1 - x0) * max(0.0, y1 - y0)
    ua = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / ua if ua > 0 else 0.0


def _inside(pt, box) -> bool:
    return box[0] <= pt[0] <= box[2] and box[1] <= pt[1] <= box[3]


def _expand(box, fx: float, fy: float | None = None) -> list[float]:
    fy = fx if fy is None else fy
    w, h = box[2] - box[0], box[3] - box[1]
    return [box[0] - w * fx, box[1] - h * fy, box[2] + w * fx, box[3] + h * fy]


def _fraction_inside(box, w, h) -> float:
    area = max(1e-6, (box[2] - box[0]) * (box[3] - box[1]))
    cx0, cy0, cx1, cy1 = max(0, box[0]), max(0, box[1]), min(w, box[2]), min(h, box[3])
    return max(0.0, cx1 - cx0) * max(0.0, cy1 - cy0) / area


def _box_center(b):
    return ((b[0] + b[2]) / 2, (b[1] + b[3]) / 2)


def _dist(a, b) -> float:
    return float(np.hypot(a[0] - b[0], a[1] - b[1]))


class Verifier:
    def __init__(self, ctx: VerifyContext, dets: list[ObsDet], texts: list[ObsText]):
        self.ctx = ctx
        self.dets = dets
        self.texts = texts
        self.findings: list[dict] = []
        self.presence_by_tag: dict[str, str] = {}
        self.h, self.w = ctx.image.shape[:2]
        self.reg = ctx.registration
        self.reg_usable = ctx.H is not None and bool(self.reg.get("usable"))

    # -- helpers -----------------------------------------------------------
    def _reg_conf(self) -> dict:
        m = self.reg.get("metrics", {}) or {}
        return {
            "status": self.reg.get("status"), "method": self.reg.get("method"),
            "inliers": m.get("inliers"), "reprojection_error_median_px": m.get("reprojection_error_median_px"),
        }

    def _project(self, bbox_pt) -> tuple[list[float] | None, list | None]:
        if not self.reg_usable or not bbox_pt:
            return None, None
        return project_bbox(self.ctx.H, bbox_pt)

    def _add(self, **kw) -> None:
        conf = kw.pop("confidences", {})
        conf.setdefault("registration", self._reg_conf())
        conf.setdefault("combined", None)
        conf.setdefault("combined_note", "No combined confidence is computed: detector, OCR and registration evidence are reported separately and have not been jointly calibrated.")
        kw["confidences"] = conf
        kw.setdefault("review_reasons", [])
        kw.setdefault("details", {})
        kw["review_reasons"] = sorted(set(kw["review_reasons"]))
        self.findings.append(kw)

    def _texts_in(self, region) -> list[ObsText]:
        return [t for t in self.texts if _inside(t.center, region)]

    def _nearest_text(self, region, target_center) -> tuple[ObsText | None, bool, str]:
        cands = self._texts_in(region)
        if not cands:
            return None, False, ""
        cands.sort(key=lambda t: _dist(t.center, target_center))
        best = cands[0]
        if len(cands) == 1:
            return best, True, "single text observation in the expected region"
        d0, d1 = _dist(cands[0].center, target_center), _dist(cands[1].center, target_center)
        unique = d0 < 0.6 * d1
        note = "nearest of %d text observations in the expected region" % len(cands) + ("" if unique else " (not clearly nearest)")
        return best, unique, note

    # -- checks ------------------------------------------------------------
    def check_alignment(self) -> None:
        st = self.reg.get("status")
        if st in ("aligned", "manual"):
            verdict, rule = "PASS", "registration_validated"
            m = self.reg.get("metrics", {})
            expl = (f"Drawing registered to the photo by {self.reg.get('method')}: {m.get('inliers')} inliers, median reprojection error "
                    f"{m.get('reprojection_error_median_px')} px; all geometric plausibility checks passed.")
            reasons = []
        else:
            verdict, rule = "UNCERTAIN", "registration_unavailable"
            expl = "Photo-to-drawing registration did not meet the quality criteria, so zone-level position checks cannot be trusted. " + "; ".join(self.reg.get("reasons", [])[:3]) + " Use manual anchor alignment to recover."
            reasons = ["registration_unavailable"]
        self._add(finding_key="drawing_alignment", check_type="drawing_alignment", zone_code=None, subject="GA drawing ↔ photo",
                  expected_value="validated homography", observed_value=st, observed_raw=None, verdict=verdict, rule=rule,
                  explanation=expl, review_reasons=reasons, bbox=None, expected_bbox=None, drawing_bbox=None,
                  details={"checks": self.reg.get("checks", []), "attempts": self.reg.get("attempts", [])})

    def check_component(self, c: ExpComp) -> None:
        ctx = self.ctx
        exp_box, exp_quad = self._project(c.body_pt)
        region_pt = c.body_pt
        if c.qty > 1 and c.zone and c.zone in ctx.zones_pt:
            region_pt = ctx.zones_pt[c.zone]
            exp_box, exp_quad = self._project(region_pt)
        base = dict(zone_code=c.zone, subject=c.tag, drawing_bbox=region_pt, expected_bbox=exp_box)
        supported = ctx.detector_available and c.cls in ctx.supported_classes
        cls_txt = (c.cls or "unknown type").replace("_", " ")
        expected_value = f"{c.qty}× {cls_txt}" if c.qty > 1 else cls_txt
        details = {"expected_class": c.cls, "class_source": c.cls_source, "drawing_match": c.match, "expected_quad": exp_quad}

        # ------ presence ------
        if "component_presence" in ctx.checks:
            reasons: list[str] = []
            if not ctx.detector_available:
                self._add(finding_key=f"component_presence:{c.tag}", check_type="component_presence", expected_value=expected_value, observed_value=None, observed_raw=None,
                          verdict="UNCERTAIN", rule="detector_unavailable", explanation="The object detector is unavailable, so component presence could not be assessed.",
                          review_reasons=["detector_unavailable"], bbox=exp_box, details=details, **base)
                self.presence_by_tag[c.tag] = "UNCERTAIN"
            elif not supported:
                why = (f"The loaded detector ({ctx.detector_kind}) has no '{c.cls}' class" if c.cls else f"Component type of {c.tag} could not be mapped to a detector class")
                self._add(finding_key=f"component_presence:{c.tag}", check_type="component_presence", expected_value=expected_value, observed_value=None, observed_raw=None,
                          verdict="UNCERTAIN", rule="unsupported_class", explanation=f"{why}; presence cannot be verified automatically and is not assumed.",
                          review_reasons=["unsupported_class"], bbox=exp_box, details=details, **base)
                self.presence_by_tag[c.tag] = "UNCERTAIN"
            elif exp_box is not None:
                self._presence_registered(c, exp_box, expected_value, details, base)
            else:
                self._presence_unregistered(c, expected_value, details, base)

        # ------ type ------
        if "component_type" in ctx.checks and supported and exp_box is not None and c.qty == 1:
            cands = [d for d in self.dets if d.above and d.cls not in LABEL_CLASSES and (_iou(d.box, exp_box) >= 0.3 or _inside(_box_center(d.box), exp_box))]
            same = [d for d in cands if d.cls == c.cls]
            other = [d for d in cands if d.cls != c.cls]
            if same and (not other or max(o.conf for o in other) < max(s.conf for s in same)):
                best = max(same, key=lambda d: d.conf)
                self._add(finding_key=f"component_type:{c.tag}", check_type="component_type", expected_value=cls_txt, observed_value=best.cls.replace("_", " "), observed_raw=None,
                          verdict="PASS", rule="type_match", explanation=f"Detection at the expected position is classified as {best.cls.replace('_', ' ')} (confidence {best.conf:.2f}), matching the specification.",
                          confidences={"detector": round(best.conf, 4)}, bbox=list(best.box), detection_id=best.id, details=details, **base)
            elif other and not same:
                best = max(other, key=lambda d: d.conf)
                self._add(finding_key=f"component_type:{c.tag}", check_type="component_type", expected_value=cls_txt, observed_value=best.cls.replace("_", " "), observed_raw=None,
                          verdict="FAIL" if best.conf >= max(0.6, ctx.detector_conf) and ctx.quality_rating != "poor" else "UNCERTAIN",
                          rule="type_mismatch" if best.conf >= max(0.6, ctx.detector_conf) else "type_mismatch_low_confidence",
                          explanation=f"Expected a {cls_txt} at {c.tag}'s position but the detector found a {best.cls.replace('_', ' ')} (confidence {best.conf:.2f}).",
                          confidences={"detector": round(best.conf, 4)}, review_reasons=[] if best.conf >= 0.6 else ["low_detector_confidence"], bbox=list(best.box), detection_id=best.id, details=details, **base)
            else:
                self._add(finding_key=f"component_type:{c.tag}", check_type="component_type", expected_value=cls_txt, observed_value=None, observed_raw=None,
                          verdict="UNCERTAIN", rule="type_not_determined", explanation="No confident detection at the expected position, so the component type could not be determined.",
                          review_reasons=["no_confident_detection"], bbox=exp_box, details=details, **base)

        # ------ device label ------
        if "device_label" in ctx.checks and c.label:
            self._label(c, details, base)

    def _presence_registered(self, c: ExpComp, exp_box, expected_value, details, base) -> None:
        ctx = self.ctx
        frac_in = _fraction_inside(exp_box, self.w, self.h)
        region = _expand(exp_box, 0.15)
        cands = [d for d in self.dets if d.cls == c.cls and (_iou(d.box, exp_box) >= 0.25 or _inside(_box_center(d.box), region))]
        strong = [d for d in cands if d.conf >= ctx.detector_conf]
        weak = [d for d in cands if d.conf < ctx.detector_conf]
        key = f"component_presence:{c.tag}"
        cls_txt = c.cls.replace("_", " ")
        if c.qty > 1:
            n = len(strong)
            obs = f"{n} detected" + (f" (+{len(weak)} low-confidence)" if weak else "")
            union = [min(d.box[0] for d in cands), min(d.box[1] for d in cands), max(d.box[2] for d in cands), max(d.box[3] for d in cands)] if cands else exp_box
            conf = {"detector_min": round(min(d.conf for d in strong), 4) if strong else None, "detector_count": n}
            if n >= c.qty:
                v, rule, expl, rs = "PASS", "quantity_met", f"{n} {cls_txt} detections in zone {c.zone or ''} (expected {c.qty}).", []
            elif n + len(weak) >= c.qty or frac_in < 0.9 or ctx.quality_rating == "poor":
                v, rule, expl, rs = "UNCERTAIN", "quantity_unconfirmed", f"Only {n} confident {cls_txt} detections in the expected region (expected {c.qty}); low-confidence detections or image limits prevent a decision.", ["weak_detection"]
            else:
                v, rule, expl, rs = "FAIL", "quantity_short", f"Only {n} {cls_txt} detections in the registered region (expected {c.qty}).", []
            self._add(finding_key=key, check_type="component_presence", expected_value=expected_value, observed_value=obs, observed_raw=None, verdict=v, rule=rule, explanation=expl,
                      confidences=conf, review_reasons=rs, bbox=union, details={**details, "detections": [d.id for d in cands]}, **base)
            self.presence_by_tag[c.tag] = v
            return
        if strong:
            best = max(strong, key=lambda d: d.conf)
            self._add(finding_key=key, check_type="component_presence", expected_value=expected_value, observed_value=f"{cls_txt} detected", observed_raw=None, verdict="PASS",
                      rule="detected_at_expected_position", explanation=f"A {cls_txt} was detected at the drawing position of {c.tag} (detector confidence {best.conf:.2f} ≥ {ctx.detector_conf}).",
                      confidences={"detector": round(best.conf, 4)}, bbox=list(best.box), detection_id=best.id, details=details, **base)
            self.presence_by_tag[c.tag] = "PASS"
            return
        reasons = []
        if weak:
            best = max(weak, key=lambda d: d.conf)
            self._add(finding_key=key, check_type="component_presence", expected_value=expected_value, observed_value=f"low-confidence {cls_txt}", observed_raw=None, verdict="UNCERTAIN",
                      rule="weak_detection", explanation=f"Only a low-confidence {cls_txt} detection ({best.conf:.2f} < {ctx.detector_conf}) at the expected position; the component may be present but could not be confirmed.",
                      confidences={"detector": round(best.conf, 4)}, review_reasons=["weak_detection"], bbox=list(best.box), detection_id=best.id, details=details, **base)
            self.presence_by_tag[c.tag] = "UNCERTAIN"
            return
        if frac_in < 0.9:
            reasons.append("region_outside_image")
        if ctx.quality_rating == "poor":
            reasons.append("poor_image_quality")
        if reasons:
            self._add(finding_key=key, check_type="component_presence", expected_value=expected_value, observed_value="not observed", observed_raw=None, verdict="UNCERTAIN",
                      rule="not_observed_unreliable_region", explanation="Nothing was detected at the expected position, but the region is " + ("partly outside the photo" if "region_outside_image" in reasons else "in a poor-quality image") + ", so absence cannot be confirmed.",
                      review_reasons=reasons, bbox=exp_box, details=details, **base)
            self.presence_by_tag[c.tag] = "UNCERTAIN"
            return
        self._add(finding_key=key, check_type="component_presence", expected_value=expected_value, observed_value="not observed", observed_raw=None, verdict="FAIL",
                  rule="missing_at_expected_position",
                  explanation=(f"No {cls_txt} was detected at the registered drawing position of {c.tag}, even at the minimum stored confidence ({min(0.05, ctx.detector_conf)}). "
                               f"The region lies inside the photo, registration is validated and the detector supports this class, so the component is reported missing."),
                  bbox=exp_box, details=details, **base)
        self.presence_by_tag[c.tag] = "FAIL"

    def _presence_unregistered(self, c: ExpComp, expected_value, details, base) -> None:
        cls_txt = c.cls.replace("_", " ")
        key = f"component_presence:{c.tag}"
        targets = {normalize(c.tag)[0]} | ({normalize(c.label)[0]} if c.label else set())
        labels = [t for t in self.texts if t.norm in targets]
        same_cls = [d for d in self.dets if d.cls == c.cls and d.above]
        for t in labels:
            for d in sorted(same_cls, key=lambda d: _dist(_box_center(d.box), t.center)):
                bh = d.box[3] - d.box[1]
                near = _expand(d.box, 0.15, 0.6)
                if _inside(t.center, near) or _dist(t.center, _box_center(d.box)) < 1.2 * bh:
                    self._add(finding_key=key, check_type="component_presence", expected_value=expected_value, observed_value=f"{cls_txt} detected", observed_raw=None, verdict="PASS",
                              rule="detected_via_label_association",
                              explanation=f"Registration is unavailable, but label '{t.raw}' was read adjacent to a {cls_txt} detection (confidence {d.conf:.2f}); presence is confirmed through the label association.",
                              confidences={"detector": round(d.conf, 4), "ocr": round(t.conf, 4)}, bbox=list(d.box), detection_id=d.id, ocr_observation_id=t.id, details=details, **base)
                    self.presence_by_tag[c.tag] = "PASS"
                    return
        self._add(finding_key=key, check_type="component_presence", expected_value=expected_value, observed_value=f"{len(same_cls)} {cls_txt} detection(s) in image", observed_raw=None, verdict="UNCERTAIN",
                  rule="registration_unavailable",
                  explanation=f"Without a validated photo-to-drawing registration the detections cannot be attributed to {c.tag}. {len(same_cls)} {cls_txt} detection(s) exist in the image overall.",
                  review_reasons=["registration_unavailable"], bbox=None, details=details, **base)
        self.presence_by_tag[c.tag] = "UNCERTAIN"

    def _label(self, c: ExpComp, details, base) -> None:
        ctx = self.ctx
        key = f"device_label:{c.tag}"
        expected = c.label
        if not ctx.ocr_available:
            self._add(finding_key=key, check_type="device_label", expected_value=expected, observed_value=None, observed_raw=None, verdict="UNCERTAIN", rule="ocr_unavailable",
                      explanation="The OCR engine is unavailable; device labels could not be read.", review_reasons=["ocr_unavailable"], bbox=None, details=details, **base)
            return
        lab_pt = c.label_pt or c.body_pt
        exp_box, _ = self._project(lab_pt)
        if exp_box is not None:
            region = _expand(exp_box, 0.6, 0.8)
            obs, unique, note = self._nearest_text(region, _box_center(exp_box))
            targeted = False
            if obs is None and ctx.ocr_at is not None:
                obs = ctx.ocr_at(_expand(exp_box, 0.25, 0.4), f"device_label:{c.tag}")
                unique, note, targeted = obs is not None, "targeted OCR of the projected label region", True
            assoc_note = f"Association: {note}." if note else ""
            dec = decide_identifier("device_label", expected, obs.raw if obs else None, obs.conf if obs else None, unique, assoc_note, ctx.policies.get("device_label"))
            self._emit_ident(key, "device_label", c.tag, expected, obs, dec, exp_box, {**details, "targeted_ocr": targeted, "search_region": region}, base)
            return
        # no registration: label must be tied to a detected component of the right class
        target = normalize(expected)[0]
        exact = [t for t in self.texts if t.norm == target]
        same_cls = [d for d in self.dets if d.cls == c.cls and d.above] if c.cls else []
        for t in exact:
            for d in same_cls:
                if _inside(t.center, _expand(d.box, 0.15, 0.6)):
                    dec = decide_identifier("device_label", expected, t.raw, t.conf, True, f"Registration unavailable; label associated with an adjacent {c.cls.replace('_', ' ')} detection.", ctx.policies.get("device_label"))
                    self._emit_ident(key, "device_label", c.tag, expected, t, dec, None, {**details, "association": "label_adjacent_to_detection", "detection_id": d.id}, base)
                    return
        note = f"Text '{expected}' was read in the image but could not be tied to a component position." if exact else f"Text '{expected}' was not read anywhere in the image."
        self._add(finding_key=key, check_type="device_label", expected_value=expected, observed_value=exact[0].norm if exact else None, observed_raw=exact[0].raw if exact else None,
                  verdict="UNCERTAIN", rule="registration_unavailable", explanation=f"Registration is unavailable. {note}",
                  confidences={"ocr": round(exact[0].conf, 4)} if exact else {}, review_reasons=["registration_unavailable"] + ([] if exact else ["no_readable_text"]),
                  bbox=list(exact[0].box) if exact else None, ocr_observation_id=exact[0].id if exact else None, details=details, **base)

    def _emit_ident(self, key, check_type, subject, expected, obs: ObsText | None, dec, exp_box, details, base) -> None:
        conf: dict = {}
        if obs:
            conf["ocr"] = round(obs.conf, 4)
        if dec.comparison:
            conf["edit_distance"] = dec.comparison.distance
            conf["text_similarity"] = round(dec.comparison.similarity, 4)
        norm = normalize(obs.raw) if obs else (None, [])
        d = {**details, "comparison": dec.comparison.to_json() if dec.comparison else None, "normalization_steps": norm[1], "ocr_region": obs.region if obs else None, "ocr_variant": obs.variant if obs else None}
        self._add(finding_key=key, check_type=check_type, expected_value=expected, observed_value=norm[0], observed_raw=obs.raw if obs else None, verdict=dec.verdict,
                  rule=dec.rule, explanation=dec.explanation, confidences=conf, review_reasons=dec.reasons, bbox=list(obs.box) if obs else exp_box,
                  ocr_observation_id=obs.id if obs else None, details=d, **base)

    def check_ferrule(self, i: ExpIdent) -> None:
        ctx = self.ctx
        subject = i.terminal_ref or i.value or "?"
        base = dict(zone_code=i.zone, subject=subject, drawing_bbox=i.marker_pt)
        details = {"terminal_ref": i.terminal_ref, "component_tag": i.component_tag, "drawing_match": i.match}
        key = f"ferrule:{subject}"
        if "ferrule_label" in ctx.checks and i.value:
            if not ctx.ocr_available:
                self._add(finding_key=key, check_type="ferrule_label", expected_value=i.value, observed_value=None, observed_raw=None, verdict="UNCERTAIN", rule="ocr_unavailable",
                          explanation="The OCR engine is unavailable; ferrules could not be read.", review_reasons=["ocr_unavailable"], bbox=None, expected_bbox=None, details=details, **base)
            elif i.marker_pt is None:
                self._add(finding_key=key, check_type="ferrule_label", expected_value=i.value, observed_value=None, observed_raw=None, verdict="UNCERTAIN", rule="not_located_in_drawing",
                          explanation=f"Ferrule {i.value} ({i.terminal_ref or 'no terminal ref'}) could not be located in the GA drawing, so there is no expected position to inspect.",
                          review_reasons=["not_located_in_drawing"], bbox=None, expected_bbox=None, details=details, **base)
            elif not self.reg_usable:
                target = normalize(i.value)[0]
                exact = [t for t in self.texts if t.norm == target]
                self._add(finding_key=key, check_type="ferrule_label", expected_value=i.value, observed_value=exact[0].norm if exact else None, observed_raw=exact[0].raw if exact else None,
                          verdict="UNCERTAIN", rule="registration_unavailable",
                          explanation=("Registration is unavailable, so the terminal position cannot be verified. " + (f"Text '{i.value}' was read elsewhere in the image." if exact else f"Text '{i.value}' was not read in the image.")),
                          confidences={"ocr": round(exact[0].conf, 4)} if exact else {}, review_reasons=["registration_unavailable"], bbox=list(exact[0].box) if exact else None,
                          expected_bbox=None, ocr_observation_id=exact[0].id if exact else None, details=details, **base)
            else:
                exp_box, _ = self._project(i.marker_pt)
                region = _expand(exp_box, 0.45, 0.9)
                obs, unique, note = self._nearest_text(region, _box_center(exp_box))
                targeted = False
                if obs is None and ctx.ocr_at is not None:
                    obs = ctx.ocr_at(_expand(exp_box, 0.25, 0.5), f"ferrule:{subject}")
                    unique, note, targeted = obs is not None, "targeted OCR of the projected ferrule region", True
                dec = decide_identifier("ferrule", i.value, obs.raw if obs else None, obs.conf if obs else None, unique, f"Association: {note}." if note else "", ctx.policies.get("ferrule"))
                self._emit_ident(key, "ferrule_label", subject, i.value, obs, dec, exp_box, {**details, "targeted_ocr": targeted, "search_region": region}, {**base, "expected_bbox": exp_box})
        if "wire_color" in ctx.checks and i.wire_color:
            self._wire_color(i, base, details)

    def _wire_color(self, i: ExpIdent, base, details) -> None:
        key = f"wire_color:{i.terminal_ref or i.value}"
        expected = canonical_color(i.wire_color)
        common = dict(finding_key=key, check_type="wire_color", expected_value=expected, observed_raw=None)
        if not self.reg_usable or i.marker_pt is None:
            self._add(**common, observed_value=None, verdict="UNCERTAIN", rule="no_wire_region",
                      explanation="Wire colour check (experimental) needs a validated registration and a located ferrule/terminal; neither the wire path nor its colour can be sampled.",
                      review_reasons=["experimental_check", "registration_unavailable" if not self.reg_usable else "not_located_in_drawing"], bbox=None, expected_bbox=None, details={**details, "experimental": True}, **base)
            return
        m = i.marker_pt
        t = i.terminal_pt
        mw = m[2] - m[0]
        y_top = m[3] + 0.5
        y_bot = (t[1] - 0.5) if t and t[1] - m[3] > 4 else m[3] + max(6.0, (m[3] - m[1]) * 1.2)
        strip_pt = [m[0] + mw * 0.1, y_top, m[2] - mw * 0.1, y_bot]
        box, _ = project_bbox(self.ctx.H, strip_pt)
        x0, y0, x1, y1 = [int(round(v)) for v in box]
        x0, y0 = max(0, x0), max(0, y0)
        x1, y1 = min(self.w, x1), min(self.h, y1)
        res = classify_strip(self.ctx.image[y0:y1, x0:x1]) if x1 - x0 > 5 and y1 - y0 > 5 else {"ok": False, "reason": "region too small"}
        d = {**details, "experimental": True, "classification": res, "sample_region_px": [x0, y0, x1, y1]}
        if not res.get("ok"):
            self._add(**common, observed_value=None, verdict="UNCERTAIN", rule="wire_region_unusable", explanation=f"Wire colour (experimental): sample region unusable ({res.get('reason')}).",
                      review_reasons=["experimental_check"], bbox=[x0, y0, x1, y1], expected_bbox=[x0, y0, x1, y1], details=d, **base)
            return
        obs = res["color"]
        frac = res["fraction"]
        light_ok = 12 <= res["lightness"] <= 95 and self.ctx.quality_rating != "poor"
        reasons = ["experimental_check"]
        if obs == expected and frac >= 0.5 and light_ok:
            v, rule, expl = "PASS", "color_match", f"Wire colour (experimental): dominant colour '{obs}' covers {frac:.0%} of the sampled wire pixels, matching the expected '{expected}'."
        elif obs != expected and frac >= 0.6 and light_ok and res["contrast_vs_background"] >= 12 and expected in {"brown", "blue", "black", "grey", "red", "white", "orange", "dark_blue", "green_yellow"}:
            v, rule, expl = "FAIL", "color_mismatch", f"Wire colour (experimental): sampled wire is predominantly '{obs}' ({frac:.0%}) but '{expected}' is expected."
        else:
            v, rule = "UNCERTAIN", "color_inconclusive"
            expl = f"Wire colour (experimental): classification '{obs}' ({frac:.0%}) is not conclusive" + ("" if light_ok else " under the current lighting") + "."
        self._add(**common, observed_value=obs, verdict=v, rule=rule, explanation=expl, confidences={"color_fraction": frac}, review_reasons=reasons if v != "PASS" else [],
                  bbox=[x0, y0, x1, y1], expected_bbox=[x0, y0, x1, y1], details=d, **base)

    def check_zones(self, comps: list[ExpComp]) -> None:
        if "zone_correspondence" not in self.ctx.checks:
            return
        by_zone: dict[str, list[str]] = {}
        for c in comps:
            if c.zone:
                by_zone.setdefault(c.zone, []).append(c.tag)
        for code, tags in sorted(by_zone.items()):
            zone_pt = self.ctx.zones_pt.get(code)
            exp_box, _ = self._project(zone_pt) if zone_pt else (None, None)
            states = {t: self.presence_by_tag.get(t, "UNCERTAIN") for t in tags}
            if zone_pt is None:
                v, rule, expl, rs = "UNCERTAIN", "zone_not_in_drawing", f"Zone {code} is referenced by the specification but was not found in the GA drawing.", ["zone_not_found"]
            elif not self.reg_usable:
                v, rule, expl, rs = "UNCERTAIN", "registration_unavailable", f"Zone {code} exists in the drawing but cannot be mapped onto the photo without registration.", ["registration_unavailable"]
            elif any(s == "FAIL" for s in states.values()):
                bad = [t for t, s in states.items() if s == "FAIL"]
                v, rule, expl, rs = "FAIL", "zone_component_missing", f"Zone {code}: {', '.join(bad)} not observed at the expected position.", []
            elif all(s == "PASS" for s in states.values()):
                v, rule, expl, rs = "PASS", "zone_complete", f"All {len(tags)} expected components of zone {code} were observed in the registered zone.", []
            else:
                pending = [t for t, s in states.items() if s != "PASS"]
                v, rule, expl, rs = "UNCERTAIN", "zone_incomplete_evidence", f"Zone {code}: {', '.join(pending)} could not be confirmed.", ["incomplete_evidence"]
            self._add(finding_key=f"zone:{code}", check_type="zone_correspondence", zone_code=code, subject=f"Zone {code}", expected_value=", ".join(tags),
                      observed_value=", ".join(f"{t}:{s}" for t, s in states.items()), observed_raw=None, verdict=v, rule=rule, explanation=expl, review_reasons=rs,
                      bbox=exp_box, expected_bbox=exp_box, drawing_bbox=zone_pt, details={"component_states": states})

    def run(self, comps: list[ExpComp], idents: list[ExpIdent]) -> list[dict]:
        if "drawing_alignment" in self.ctx.checks:
            self.check_alignment()
        for c in comps:
            self.check_component(c)
        for i in idents:
            self.check_ferrule(i)
        self.check_zones(comps)
        return self.findings
