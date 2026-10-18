"""Inspection pipeline orchestration with persisted, observable stages.

Each stage records pending → running → completed | failed | skipped | needs_review together with
a message and structured details. Stage outcomes reflect what actually happened: a skipped stage
always states why, and a failed stage stops the job with the error preserved.
"""
from __future__ import annotations

import copy
import time
import traceback
from dataclasses import dataclass, field

import cv2
import numpy as np
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from ..core.config import get_settings
from ..core.db import SessionLocal
from ..core.logging import get_logger
from ..core.util import jsonable, utcnow
from ..cv import draw
from ..cv.detector import get_detector
from ..cv.preprocess import PreparedImage, assess_quality, decode_image, encode_jpeg, encode_png, prepare
from ..cv.registration import RegistrationResult, project_bbox, register, text_anchor_pairs
from ..drawing.pdf_parser import ParsedDrawing, derive_zones_from_components, extract_zones, locate_identifier, parse_drawing
from ..models import (
    Detection, Drawing, DrawingZone, EvidenceAsset, ExpectedComponent, ExpectedIdentifier, Finding, InputAsset, Inspection, InspectionVersion,
    OcrObservation, ProcessingJob, ProcessingStage, Report, VersionComparison,
)
from ..ocr.engines import get_ocr
from ..ocr.normalize import normalize
from ..services.common import audit, upsert_model_config
from ..storage.local import get_storage
from .spreadsheet import parse_records
from .taxonomy import canonical_class
from .verify import ExpComp, ExpIdent, ObsDet, ObsText, Verifier, VerifyContext

log = get_logger("pipeline")

STAGES: list[tuple[str, str]] = [
    ("validation", "Input validation"),
    ("preprocessing", "Image preprocessing"),
    ("drawing", "Drawing extraction"),
    ("detection", "Object detection (YOLOv8)"),
    ("ocr", "OCR label discovery"),
    ("registration", "Photo-to-drawing registration"),
    ("verification", "Verification rules"),
    ("evidence", "Evidence generation"),
    ("report", "Report generation"),
]

ALL_CHECKS = ["component_presence", "component_type", "device_label", "ferrule_label", "wire_color", "zone_correspondence", "drawing_alignment"]
CHECK_INFO = {
    "component_presence": {"title": "Component presence", "status": "implemented", "requires": "detector with the component's class"},
    "component_type": {"title": "Component type", "status": "implemented", "requires": "detector with the component's class + registration"},
    "device_label": {"title": "Device-label verification", "status": "implemented", "requires": "OCR"},
    "ferrule_label": {"title": "Ferrule-label verification", "status": "implemented", "requires": "OCR + registration"},
    "wire_color": {"title": "Wire-colour verification", "status": "experimental", "requires": "registration; colour classification is heuristic"},
    "zone_correspondence": {"title": "Zone correspondence", "status": "implemented", "requires": "zones in the drawing + registration"},
    "drawing_alignment": {"title": "Drawing alignment", "status": "implemented", "requires": "GA drawing"},
}
DEFAULT_CONFIG = {
    "checks": ["component_presence", "component_type", "device_label", "ferrule_label", "zone_correspondence", "drawing_alignment"],
    "drawing_page": 0,
    "sheets": None,
    "preprocess": {"clahe": True, "denoise": False, "deskew": False},
    "detector": {"conf": None, "iou": None, "tiling": None},
    "policies": {"device_label": {"mode": "confusion_aware"}, "ferrule": {"mode": "confusion_aware"}},
    "manual_anchors": None,
    "manual_zones": None,
}


def merged_config(cfg: dict | None) -> dict:
    out = copy.deepcopy(DEFAULT_CONFIG)
    for k, v in (cfg or {}).items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = {**out[k], **v}
        else:
            out[k] = v
    return out


class StageSkipped(Exception):
    def __init__(self, reason: str, details: dict | None = None):
        super().__init__(reason)
        self.details = details or {}


class JobCancelled(Exception):
    pass


@dataclass
class RunState:
    version: InspectionVersion
    inspection: Inspection
    config: dict
    photo_asset: InputAsset | None = None
    drawing_asset: InputAsset | None = None
    list_asset: InputAsset | None = None
    prepared: PreparedImage | None = None
    quality: dict = field(default_factory=dict)
    original_key: str | None = None
    parsed: ParsedDrawing | None = None
    drawing_row: Drawing | None = None
    zones_pt: dict = field(default_factory=dict)
    detector_available: bool = False
    detector_kind: str = "none"
    supported_classes: set = field(default_factory=set)
    detector_conf: float = 0.35
    ocr_available: bool = False
    registration: RegistrationResult | None = None
    stage_details: dict = field(default_factory=dict)


class PipelineRunner:
    def __init__(self, db: Session, job: ProcessingJob):
        self.db = db
        self.job = job
        self.storage = get_storage()
        self.settings = get_settings()

    # -- stage bookkeeping ------------------------------------------------
    def _stage(self, name: str) -> ProcessingStage:
        return next(s for s in self.job.stages if s.name == name)

    def _check_cancel(self) -> None:
        self.db.refresh(self.job, attribute_names=["cancel_requested"])
        if self.job.cancel_requested:
            raise JobCancelled()

    def run(self) -> None:
        job = self.job
        ver = self.db.get(InspectionVersion, job.version_id)
        insp = self.db.get(Inspection, job.inspection_id)
        st = RunState(version=ver, inspection=insp, config=merged_config(ver.config))
        job.status = "running"
        job.started_at = utcnow()
        ver.status = "running"
        ver.started_at = job.started_at
        ver.error = None
        audit(self.db, "run_started", "version", ver.id, insp.id, {"job_id": job.id, "version_no": ver.version_no})
        self.db.commit()
        t_job = time.time()
        handlers = {
            "validation": self.stage_validation, "preprocessing": self.stage_preprocessing, "drawing": self.stage_drawing,
            "detection": self.stage_detection, "ocr": self.stage_ocr, "registration": self.stage_registration,
            "verification": self.stage_verification, "evidence": self.stage_evidence, "report": self.stage_report,
        }
        for name, _title in STAGES:
            stage = self._stage(name)
            try:
                self._check_cancel()
            except JobCancelled:
                self._cancel(st, stage)
                return
            stage.status = "running"
            stage.started_at = utcnow()
            job.current_stage = name
            self.db.commit()
            t0 = time.time()
            try:
                result = handlers[name](st) or {}
                stage.status = result.get("status", "completed")
                stage.message = result.get("message")
                stage.details = jsonable(result.get("details", {}))
            except StageSkipped as sk:
                stage.status = "skipped"
                stage.message = str(sk)
                stage.details = jsonable(sk.details)
            except JobCancelled:
                stage.finished_at = utcnow()
                stage.duration_ms = int((time.time() - t0) * 1000)
                self._cancel(st, stage)
                return
            except Exception as exc:
                self.db.rollback()
                stage = self._stage(name)
                stage.status = "failed"
                stage.message = f"{type(exc).__name__}: {exc}"
                stage.details = {"traceback_tail": traceback.format_exc().splitlines()[-6:]}
                stage.finished_at = utcnow()
                stage.duration_ms = int((time.time() - t0) * 1000)
                for later in self.job.stages:
                    if later.order > stage.order and later.status == "pending":
                        later.status = "skipped"
                        later.message = f"Not executed: stage '{name}' failed"
                job.status = "failed"
                job.error = f"Stage '{name}' failed: {type(exc).__name__}: {exc}"
                job.finished_at = utcnow()
                ver = self.db.get(InspectionVersion, job.version_id)
                ver.status = "failed"
                ver.error = job.error
                ver.completed_at = job.finished_at
                ver.duration_ms = int((time.time() - t_job) * 1000)
                audit(self.db, "run_failed", "version", ver.id, ver.inspection_id, {"job_id": job.id, "stage": name, "error": str(exc)[:500]})
                self.db.commit()
                log.error("Job failed at %s: %s", name, exc, extra={"ctx": {"job_id": job.id, "stage": name}})
                return
            stage.finished_at = utcnow()
            stage.duration_ms = int((time.time() - t0) * 1000)
            self.db.commit()
        ver = st.version
        job.status = "completed"
        job.current_stage = None
        job.finished_at = utcnow()
        ver.status = "completed"
        ver.completed_at = job.finished_at
        ver.duration_ms = int((time.time() - t_job) * 1000)
        audit(self.db, "run_completed", "version", ver.id, ver.inspection_id, {"job_id": job.id, "summary": ver.summary, "duration_ms": ver.duration_ms})
        self.db.commit()
        if ver.parent_version_id:
            from .comparison import compare_versions

            compare_versions(self.db, ver.parent_version_id, ver.id)
            self.db.commit()
        log.info("Job completed", extra={"ctx": {"job_id": job.id, "duration_ms": ver.duration_ms, **(ver.summary or {})}})

    def _cancel(self, st: RunState, stage: ProcessingStage) -> None:
        stage.status = "skipped"
        stage.message = "Cancelled by user"
        for s in self.job.stages:
            if s.status in ("pending", "running"):
                s.status = "skipped"
                s.message = "Cancelled by user"
        self.job.status = "cancelled"
        self.job.finished_at = utcnow()
        st.version.status = "cancelled"
        st.version.error = "Cancelled by user"
        audit(self.db, "run_cancelled", "version", st.version.id, st.version.inspection_id, {"job_id": self.job.id})
        self.db.commit()

    # -- helpers ------------------------------------------------------------
    def _evidence(self, st: RunState, kind: str, title: str, img: np.ndarray | None, operation: str, algorithm: str | None = None,
                  finding_id: str | None = None, bbox=None, source_asset_id: str | None = None, error: str | None = None, fmt: str = "jpg") -> EvidenceAsset:
        ev = EvidenceAsset(inspection_id=st.inspection.id, version_id=st.version.id, finding_id=finding_id, kind=kind, title=title, operation=operation,
                           algorithm=algorithm, bbox=bbox, source_asset_id=source_asset_id, error=error)
        if img is not None and img.size:
            data = encode_png(img) if fmt == "png" else encode_jpeg(img, 90)
            key = self.storage.make_key("inspections", st.inspection.id, st.version.id, "evidence", ext=fmt)
            sha, _ = self.storage.put_bytes(key, data)
            ev.storage_key, ev.sha256 = key, sha
            ev.content_type = "image/png" if fmt == "png" else "image/jpeg"
            ev.height, ev.width = img.shape[:2]
        self.db.add(ev)
        self.db.flush()
        return ev

    def _clear_derived(self, version_id: str) -> None:
        """Remove partial results of a failed/cancelled attempt of THIS version before re-running it."""
        self.db.execute(delete(EvidenceAsset).where(EvidenceAsset.version_id == version_id))
        self.db.execute(delete(Report).where(Report.version_id == version_id))
        self.db.execute(delete(VersionComparison).where(VersionComparison.to_version_id == version_id))
        for model in (Finding, OcrObservation, Detection, ExpectedComponent, ExpectedIdentifier):
            self.db.execute(delete(model).where(model.version_id == version_id))
        for d in self.db.scalars(select(Drawing).where(Drawing.version_id == version_id)):
            self.db.delete(d)
        self.db.flush()

    # -- stages ---------------------------------------------------------------
    def stage_validation(self, st: RunState) -> dict:
        self._clear_derived(st.version.id)
        assets = self.db.scalars(select(InputAsset).where(InputAsset.version_id == st.version.id).order_by(InputAsset.created_at)).all()
        for a in assets:
            if a.kind == "photo":
                st.photo_asset = a
            elif a.kind == "drawing":
                st.drawing_asset = a
            elif a.kind == "expected_list":
                st.list_asset = a
        problems, warnings = [], []
        if not st.photo_asset:
            problems.append("No cabinet photograph uploaded.")
        if not st.list_asset:
            problems.append("No expected component/wire list uploaded.")
        if not st.drawing_asset:
            warnings.append("No GA drawing uploaded: registration, zone and position-based checks will be UNCERTAIN.")
        for a in (st.photo_asset, st.drawing_asset, st.list_asset):
            if a and not self.storage.exists(a.storage_key):
                problems.append(f"Stored file for {a.original_filename} is missing.")
        if problems:
            raise ValueError(" ".join(problems))
        parsed = parse_records(self.storage.read_bytes(st.list_asset.storage_key), st.list_asset.original_filename, st.config.get("sheets"))
        if not parsed["components"] and not parsed["identifiers"]:
            raise ValueError("The expected list produced no component or ferrule records; check the sheet selection and column mapping.")
        for c in parsed["components"]:
            cls, src = canonical_class(c["component_type"], c["tag"])
            self.db.add(ExpectedComponent(version_id=st.version.id, tag=c["tag"], zone_code=c["zone_code"], component_type=c["component_type"], canonical_class=cls,
                                          expected_label=c["expected_label"], quantity=c["quantity"], notes=(c["notes"] or "") + (" [class inferred from tag prefix]" if src == "tag_prefix" else "") or None,
                                          source_sheet=c["source_sheet"], source_row=c["source_row"]))
        for i in parsed["identifiers"]:
            self.db.add(ExpectedIdentifier(version_id=st.version.id, kind=i["kind"], value=i["value"], terminal_ref=i["terminal_ref"], wire_color=i["wire_color"],
                                           component_tag=i["component_tag"], zone_code=i["zone_code"], source_sheet=i["source_sheet"], source_row=i["source_row"]))
        det = get_detector()
        st.detector_available = det.load()
        st.detector_kind = det.kind
        st.supported_classes = det.supported_cabinet_classes
        st.detector_conf = st.config["detector"].get("conf") or self.settings.detector_conf
        ocr = get_ocr()
        st.ocr_available = ocr.load()
        if not st.detector_available:
            warnings.append(f"Detector unavailable: {det.last_error}")
        elif det.kind == "generic_coco":
            warnings.append("Only generic COCO weights are loaded; cabinet component checks will be UNCERTAIN.")
        if not st.ocr_available:
            warnings.append(f"OCR unavailable: {ocr.last_error}")
        writable, wmsg = self.storage.writable()
        if not writable:
            raise RuntimeError(f"Storage is not writable: {wmsg}")
        if st.detector_available:
            dmc = upsert_model_config(self.db, "detector", det.model_name, {"weights": det.model_name, "kind": det.kind, "device": det.device, "conf": st.detector_conf,
                                                                            "iou": self.settings.detector_iou, "imgsz": self.settings.detector_imgsz, "tiling": self.settings.detector_tiling,
                                                                            "tile_size": self.settings.detector_tile_size})
            st.version.detector_config_id = dmc.id
        if st.ocr_available:
            o = ocr.status()
            omc = upsert_model_config(self.db, "ocr", f"{o['engine']} {o['engine_version']}", {"engine": o["engine"], "version": o["engine_version"], "languages": o["languages"], "allowlist": o["allowlist"]})
            st.version.ocr_config_id = omc.id
        details = {
            "expected_components": len(parsed["components"]), "expected_identifiers": len(parsed["identifiers"]), "list_warnings": parsed["warnings"][:50],
            "sheets_used": parsed["sheets"], "detector": {"available": st.detector_available, "kind": st.detector_kind, "supported_classes": sorted(st.supported_classes)},
            "ocr": {"available": st.ocr_available, "engine": ocr.engine.name if ocr.engine else None}, "warnings": warnings, "checks": st.config["checks"],
        }
        msg = f"{len(parsed['components'])} expected components, {len(parsed['identifiers'])} wire/ferrule records"
        return {"status": "needs_review" if warnings else "completed", "message": msg + (f"; {len(warnings)} warning(s)" if warnings else ""), "details": details}

    def stage_preprocessing(self, st: RunState) -> dict:
        data = self.storage.read_bytes(st.photo_asset.storage_key)
        dec = decode_image(data)
        pp = st.config["preprocess"]
        st.prepared = prepare(dec.bgr, clahe=pp.get("clahe", True), denoise=pp.get("denoise", False), deskew=pp.get("deskew", False))
        st.quality = assess_quality(dec.bgr)
        if dec.exif_orientation != 1:
            ev = self._evidence(st, "original_photo", "Original photo (EXIF orientation applied)", dec.bgr, "exif_orientation_applied", "PIL ImageOps.exif_transpose",
                                source_asset_id=st.photo_asset.id, fmt="jpg")
        else:
            ev = EvidenceAsset(inspection_id=st.inspection.id, version_id=st.version.id, kind="original_photo", title="Original photo", storage_key=st.photo_asset.storage_key,
                               content_type=st.photo_asset.content_type, width=dec.bgr.shape[1], height=dec.bgr.shape[0], sha256=st.photo_asset.sha256,
                               operation="uploaded_original", algorithm=None, source_asset_id=st.photo_asset.id)
            self.db.add(ev)
        st.original_key = ev.storage_key
        self._evidence(st, "processed_photo", "Processed photo (" + ", ".join(t["op"] for t in st.prepared.transforms if not t.get("skipped")) + ")",
                       st.prepared.processed, "preprocessing", "OpenCV", source_asset_id=st.photo_asset.id)
        st.version.preprocessing = jsonable({"quality": st.quality, "transforms": st.prepared.transforms, "scale": st.prepared.scale, "exif_orientation": dec.exif_orientation,
                                    "original_size": [dec.bgr.shape[1], dec.bgr.shape[0]], "original_storage_key_evidence": ev.id})
        msg = f"{dec.bgr.shape[1]}×{dec.bgr.shape[0]}px, quality {st.quality['rating']}"
        return {"status": "needs_review" if st.quality["rating"] == "poor" else "completed", "message": msg, "details": {"quality": st.quality, "transforms": st.prepared.transforms}}

    def stage_drawing(self, st: RunState) -> dict:
        if not st.drawing_asset:
            raise StageSkipped("No GA drawing supplied; zone and position information is unavailable.")
        page = int(st.config.get("drawing_page") or 0)
        ocr = get_ocr() if st.ocr_available else None
        pd = parse_drawing(self.storage.read_bytes(st.drawing_asset.storage_key), page, ocr=ocr)
        st.parsed = pd
        ev = self._evidence(st, "drawing_page", f"GA drawing page {page + 1}", pd.render, "pdf_render", f"PyMuPDF @ {pd.render_scale:.2f} px/pt", source_asset_id=st.drawing_asset.id, fmt="png")
        drow = Drawing(version_id=st.version.id, asset_id=st.drawing_asset.id, page_index=page, page_count=(st.drawing_asset.analysis or {}).get("page_count", 1),
                       page_width=pd.width, page_height=pd.height, content_kind=pd.kind, render_storage_key=ev.storage_key, render_scale=pd.render_scale,
                       text_spans=[{"text": w.text, "bbox": [round(v, 2) for v in w.bbox], "source": w.source} for w in pd.words][:5000],
                       rects=[{"bbox": [round(v, 2) for v in r.bbox], "dashed": r.dashed} for r in pd.rects][:5000], warnings=list(pd.warnings), stats=pd.stats)
        self.db.add(drow)
        self.db.flush()
        st.drawing_row = drow
        comps = self.db.scalars(select(ExpectedComponent).where(ExpectedComponent.version_id == st.version.id)).all()
        idents = self.db.scalars(select(ExpectedIdentifier).where(ExpectedIdentifier.version_id == st.version.id)).all()
        located_c, located_i = 0, 0
        for c in comps:
            loc = locate_identifier(pd, c.tag)
            if not loc["found"] and c.expected_label and c.expected_label != c.tag:
                loc = locate_identifier(pd, c.expected_label)
            if loc["found"]:
                c.drawing_bbox, c.drawing_label_bbox, c.drawing_match = loc["body_bbox"], loc["label_bbox"], loc["match"]
                located_c += 1
                if loc.get("note"):
                    drow.warnings = drow.warnings + [{"code": "multiple_occurrences", "message": f"{c.tag}: {loc['note']}"}]
            else:
                c.drawing_match = "not_found"
        for i in idents:
            loc = locate_identifier(pd, i.value) if i.value else {"found": False}
            if loc["found"]:
                i.drawing_bbox = loc["label_bbox"]
                i.drawing_match = loc["match"]
                if loc["match"] == "label_plate+body":
                    i.drawing_match = "marker+terminal"
                    i.drawing_terminal_bbox = loc["body_bbox"]
                located_i += 1
            else:
                i.drawing_match = "not_found"
        manual = st.config.get("manual_zones")
        if manual:
            zones = [{"code": z["code"], "name": z.get("name"), "bbox": z["bbox"], "source": "manual"} for z in manual]
        else:
            zones = extract_zones(pd)
            if not zones:
                by_zone: dict[str, list] = {}
                for c in comps:
                    if c.zone_code and c.drawing_bbox:
                        by_zone.setdefault(c.zone_code, []).append(c.drawing_bbox)
                zones = derive_zones_from_components(by_zone)
                if zones:
                    drow.warnings = drow.warnings + [{"code": "zones_derived", "message": "No zone frames found in the drawing; zones were derived from the positions of their components."}]
        for z in zones:
            b = z["bbox"]
            self.db.add(DrawingZone(drawing_id=drow.id, code=z["code"], name=z.get("name"), x0=b[0], y0=b[1], x1=b[2], y1=b[3], source=z["source"]))
            st.zones_pt[z["code"]] = b
        not_found = [c.tag for c in comps if c.drawing_match == "not_found"] + [i.value for i in idents if i.value and i.drawing_match == "not_found"]
        details = {"kind": pd.kind, "stats": pd.stats, "zones": len(zones), "zone_codes": [z["code"] for z in zones], "components_located": located_c,
                   "components_total": len(comps), "identifiers_located": located_i, "identifiers_total": len([i for i in idents if i.value]),
                   "not_located": not_found[:50], "warnings": drow.warnings}
        msg = f"{pd.kind} page: {len(zones)} zones, {located_c}/{len(comps)} components and {located_i}/{len([i for i in idents if i.value])} ferrules located"
        status = "needs_review" if (not zones or not_found or pd.kind == "raster") else "completed"
        return {"status": status, "message": msg, "details": details}

    def stage_detection(self, st: RunState) -> dict:
        if not st.detector_available:
            raise StageSkipped(f"Detector unavailable: {get_detector().last_error}")
        det = get_detector()
        cfg = st.config["detector"]
        run = det.detect(st.prepared.processed, conf=cfg.get("conf"), iou=cfg.get("iou"), tiling=cfg.get("tiling"))
        counts: dict[str, int] = {}
        vis = st.prepared.original.copy()
        for d in run.detections:
            box = st.prepared.box_to_original(d.box)
            above = d.confidence >= run.conf_threshold
            self.db.add(Detection(version_id=st.version.id, class_id=d.class_id, class_name=d.class_name, confidence=round(d.confidence, 5), above_threshold=above,
                                  x0=box[0], y0=box[1], x1=box[2], y1=box[3], source=d.source, model_name=run.model_name))
            if above:
                counts[d.class_name] = counts.get(d.class_name, 0) + 1
                draw.box(vis, box, draw.CLASS_BGR.get(d.class_name, (200, 200, 200)), f"{d.class_name} {d.confidence:.2f}")
        self._evidence(st, "detections_overlay", f"YOLOv8 detections ({run.model_name})", vis, "object_detection", f"Ultralytics YOLOv8 {run.model_name} conf≥{run.conf_threshold}")
        details = {"model": run.model_name, "kind": det.kind, "device": run.device, "duration_ms": run.duration_ms, "tiles": run.tiles, "imgsz": run.imgsz,
                   "conf_threshold": run.conf_threshold, "iou_threshold": run.iou_threshold, "stored_min_conf": run.min_store_conf,
                   "counts_above_threshold": counts, "total_stored": len(run.detections), "params": run.params, "limitations": det.status()["limitations"]}
        msg = f"{sum(counts.values())} detections ≥ {run.conf_threshold} ({len(run.detections)} stored ≥ {run.min_store_conf}) in {run.duration_ms} ms on {run.device}, {run.tiles} tiles"
        return {"status": "needs_review" if det.kind == "generic_coco" else "completed", "message": msg, "details": details}

    def stage_ocr(self, st: RunState) -> dict:
        if not st.ocr_available:
            raise StageSkipped(f"OCR unavailable: {get_ocr().last_error}")
        ocr = get_ocr()
        t0 = time.time()
        regions = ocr.read(st.prepared.processed, canvas=self.settings.ocr_full_image_canvas)
        obs: list[dict] = []
        for r in regions:
            norm, steps = normalize(r.text)
            if not norm:
                continue
            box = st.prepared.box_to_original(r.box)
            poly = st.prepared.to_original(np.array(r.polygon)).tolist()
            obs.append({"raw": r.text, "norm": norm, "steps": steps, "conf": r.confidence, "box": box, "poly": poly, "region": "full", "variant": "full_image_clahe", "alts": [], "det": None})
        full_ms = int((time.time() - t0) * 1000)
        # crop OCR on detected label-carrying objects (original resolution)
        t1 = time.time()
        label_dets = self.db.scalars(select(Detection).where(Detection.version_id == st.version.id, Detection.above_threshold.is_(True),
                                                             Detection.class_name.in_(["device_label", "wire_marker"]))).all()
        crops = 0
        for i, d in enumerate(label_dets):
            if i % 8 == 0:
                self._check_cancel()
            reading = self._read_crop(st, [d.x0, d.y0, d.x1, d.y1], pad=0.12)
            if reading:
                reading["det"] = d.id
                reading["region"] = "detection_crop"
                obs.append(reading)
                crops += 1
        crop_ms = int((time.time() - t1) * 1000)
        kept = dedupe_observations(obs)
        rows = 0
        for o in kept:
            self.db.add(OcrObservation(version_id=st.version.id, raw_text=o["raw"][:250], normalized_text=o["norm"][:250], normalization_steps=o["steps"], confidence=round(o["conf"], 5),
                                       polygon=o["poly"], x0=o["box"][0], y0=o["box"][1], x1=o["box"][2], y1=o["box"][3], region=o["region"], variant=o["variant"],
                                       alternatives=o["alts"], engine=ocr.engine.name, detection_id=o.get("det")))
            rows += 1
        vis = st.prepared.original.copy()
        for o in kept:
            draw.box(vis, o["box"], (255, 220, 80) if o["region"] == "full" else (255, 140, 255), f"{o['norm']} {o['conf']:.2f}")
        self._evidence(st, "ocr_overlay", f"OCR observations ({ocr.engine.name})", vis, "ocr", f"{ocr.engine.name} full image + detection crops")
        details = {"engine": ocr.engine.name, "full_image_regions": len(regions), "full_image_ms": full_ms, "detection_crops": len(label_dets), "crop_readings": crops,
                   "crop_ms": crop_ms, "observations_after_dedup": rows, "allowlist": ocr.status()["allowlist"]}
        return {"message": f"{rows} text observations ({len(regions)} full-image regions, {crops} crop readings) via {ocr.engine.name}", "details": details}

    def _read_crop(self, st: RunState, box: list[float], pad: float = 0.12) -> dict | None:
        img = st.prepared.original
        crop, cbox = draw.crop_with_padding(img, box, pad_frac=pad, min_pad=4)
        if crop.size == 0:
            return None
        variants = get_ocr().read_crop_variants(crop)
        good = [v for v in variants if v.get("normalized")]
        if not good:
            return None
        best = max(good, key=lambda v: v["confidence"])
        b = best.get("box") or [0, 0, crop.shape[1], crop.shape[0]]
        gbox = [cbox[0] + b[0], cbox[1] + b[1], cbox[0] + b[2], cbox[1] + b[3]]
        alts = [{"variant": v["variant"], "text": v.get("text"), "normalized": v.get("normalized"), "confidence": v.get("confidence")} for v in variants if v is not best]
        return {"raw": best["text"], "norm": best["normalized"], "steps": best["steps"], "conf": float(best["confidence"]), "box": gbox,
                "poly": [[gbox[0], gbox[1]], [gbox[2], gbox[1]], [gbox[2], gbox[3]], [gbox[0], gbox[3]]], "variant": best["variant"], "alts": alts, "det": None}

    def stage_registration(self, st: RunState) -> dict:
        manual = st.config.get("manual_anchors")
        if not st.parsed and not manual:
            st.registration = RegistrationResult("unavailable", None, None, reasons=["no GA drawing was supplied"])
            st.version.registration = st.registration.to_json()
            raise StageSkipped("No GA drawing: registration not possible.")
        dsize = (st.parsed.width, st.parsed.height) if st.parsed else (1.0, 1.0)
        pairs = None
        if st.ocr_available and st.parsed:
            dwords = [(w.norm, w.bbox) for w in st.parsed.words]
            pobs = [(o.normalized_text, (o.x0, o.y0, o.x1, o.y1), o.confidence) for o in self.db.scalars(select(OcrObservation).where(OcrObservation.version_id == st.version.id))]
            pairs = text_anchor_pairs(dwords, pobs)
        reg = register(st.parsed.render if st.parsed else None, st.parsed.render_scale if st.parsed else 1.0, dsize, st.prepared.original, pairs, manual)
        st.registration = reg
        st.version.registration = reg.to_json()
        if reg.H is not None and st.parsed is not None:
            S = np.diag([st.parsed.render_scale, st.parsed.render_scale, 1.0])
            Hr = reg.H @ np.linalg.inv(S)
            ph, pw = st.prepared.original.shape[:2]
            warped = cv2.warpPerspective(st.parsed.render, Hr, (pw, ph), borderValue=(255, 255, 255))
            ink = (cv2.cvtColor(warped, cv2.COLOR_BGR2GRAY) < 160)
            over = st.prepared.original.copy()
            over[ink] = (0.35 * over[ink] + 0.65 * np.array([255, 230, 40])).astype(np.uint8)
            for code, b in st.zones_pt.items():
                _, quad = project_bbox(reg.H, b)
                draw.poly(over, quad, (255, 180, 0), fill_alpha=0.08)
                draw.label(over, code, int(quad[0][0]) + 4, int(quad[0][1]) + 28, (255, 180, 0))
            for c in reg.correspondences[:150]:
                p = [int(v) for v in c["photo"]]
                cv2.circle(over, tuple(p), 9, (60, 220, 60) if c.get("inlier") else (60, 60, 230), 3)
            self._evidence(st, "registration_overlay", f"Registered drawing overlay ({reg.method or reg.status})", over, "photo_to_drawing_registration",
                           f"{reg.method}; H: drawing pt → photo px", source_asset_id=st.drawing_asset.id if st.drawing_asset else None)
        msg = {
            "aligned": f"Aligned by {reg.method}: {reg.metrics.get('inliers')} inliers, median error {reg.metrics.get('reprojection_error_median_px')} px",
            "manual": f"Manual anchors accepted ({reg.metrics.get('inliers')} pairs)",
            "insufficient": "Registration rejected by quality checks: " + "; ".join(reg.reasons[:2]),
            "failed": "Registration failed: " + "; ".join(reg.reasons[:2]),
        }.get(reg.status, reg.status)
        return {"status": "completed" if reg.usable else "needs_review", "message": msg, "details": {"status": reg.status, "method": reg.method, "metrics": reg.metrics,
                                                                                                         "attempts": reg.attempts, "anchor_candidates": len(pairs or [])}}

    def stage_verification(self, st: RunState) -> dict:
        vid = st.version.id
        comps = self.db.scalars(select(ExpectedComponent).where(ExpectedComponent.version_id == vid)).all()
        idents = self.db.scalars(select(ExpectedIdentifier).where(ExpectedIdentifier.version_id == vid)).all()
        dets = [ObsDet(d.id, d.class_name, d.confidence, (d.x0, d.y0, d.x1, d.y1), d.above_threshold) for d in self.db.scalars(select(Detection).where(Detection.version_id == vid))]
        texts = [ObsText(o.id, o.raw_text, o.normalized_text, o.confidence, (o.x0, o.y0, o.x1, o.y1), o.region, o.variant)
                 for o in self.db.scalars(select(OcrObservation).where(OcrObservation.version_id == vid))]
        reg = st.registration or RegistrationResult("unavailable", None, None, reasons=["registration stage did not run"])
        targeted = {"count": 0}

        def ocr_at(box, purpose):
            self._check_cancel()
            reading = self._read_crop(st, box, pad=0.0)
            targeted["count"] += 1
            if not reading:
                return None
            row = OcrObservation(version_id=vid, raw_text=reading["raw"][:250], normalized_text=reading["norm"][:250], normalization_steps=reading["steps"],
                                 confidence=round(reading["conf"], 5), polygon=reading["poly"], x0=reading["box"][0], y0=reading["box"][1], x1=reading["box"][2], y1=reading["box"][3],
                                 region="targeted_crop", variant=reading["variant"], alternatives=reading["alts"] + [{"purpose": purpose}], engine=get_ocr().engine.name)
            self.db.add(row)
            self.db.flush()
            t = ObsText(row.id, row.raw_text, row.normalized_text, row.confidence, (row.x0, row.y0, row.x1, row.y1), "targeted_crop", row.variant)
            texts.append(t)
            return t

        ctx = VerifyContext(H=reg.H if reg.usable else None, registration=reg.to_json(), image=st.prepared.original, quality_rating=st.quality.get("rating", "good"),
                            supported_classes=st.supported_classes, detector_kind=st.detector_kind, detector_available=st.detector_available, detector_conf=st.detector_conf,
                            ocr_available=st.ocr_available, zones_pt=st.zones_pt, checks=set(st.config["checks"]), policies=st.config.get("policies") or {},
                            ocr_at=ocr_at if st.ocr_available else None)
        v = Verifier(ctx, dets, texts)
        drafts = v.run(
            [ExpComp(c.id, c.tag, c.zone_code, c.canonical_class, "type" if c.component_type else "tag_prefix", c.expected_label, c.quantity, c.drawing_bbox, c.drawing_label_bbox, c.drawing_match) for c in comps],
            [ExpIdent(i.id, i.kind, i.value, i.terminal_ref, i.wire_color, i.component_tag, i.zone_code, i.drawing_bbox, i.drawing_terminal_bbox, i.drawing_match) for i in idents],
        )
        det_m = get_detector()
        o = get_ocr().status()
        model_refs = {"detector": det_m.model_name if st.detector_available else None, "detector_config_id": st.version.detector_config_id,
                      "ocr": f"{o['engine']} {o['engine_version']}" if st.ocr_available else None, "ocr_config_id": st.version.ocr_config_id}
        counts = {"PASS": 0, "FAIL": 0, "UNCERTAIN": 0}
        by_check: dict[str, dict] = {}
        for n, d in enumerate(drafts, 1):
            f = Finding(inspection_id=st.inspection.id, version_id=vid, seq=n, model_refs=model_refs, **jsonable(d))
            self.db.add(f)
            counts[d["verdict"]] += 1
            by_check.setdefault(d["check_type"], {"PASS": 0, "FAIL": 0, "UNCERTAIN": 0})[d["verdict"]] += 1
        st.version.summary = jsonable({"total": len(drafts), "pass": counts["PASS"], "fail": counts["FAIL"], "uncertain": counts["UNCERTAIN"], "by_check": by_check,
                              "registration": reg.status, "detector_kind": st.detector_kind, "targeted_ocr_reads": targeted["count"]})
        self.db.flush()
        msg = f"{len(drafts)} findings: {counts['PASS']} PASS, {counts['FAIL']} FAIL, {counts['UNCERTAIN']} UNCERTAIN"
        return {"status": "needs_review" if counts["UNCERTAIN"] else "completed", "message": msg, "details": {"counts": counts, "by_check": by_check, "targeted_ocr_reads": targeted["count"]}}

    def stage_evidence(self, st: RunState) -> dict:
        vid = st.version.id
        findings = self.db.scalars(select(Finding).where(Finding.version_id == vid).order_by(Finding.seq)).all()
        img = st.prepared.original
        overview = img.copy()
        made, missing = 0, 0
        for f in findings:
            box = f.bbox or f.expected_bbox
            if not box:
                continue
            col = draw.VERDICT_BGR[f.verdict]
            draw.box(overview, box, col, f"#{f.seq} {f.check_type.replace('_', ' ')} {f.verdict}", dashed=f.bbox is None)
        self._evidence(st, "annotated_photo", "Annotated photo — findings by verdict", overview, "findings_overlay", "OpenCV annotation")
        for i, f in enumerate(findings):
            if i % 10 == 0:
                self._check_cancel()
            box = f.bbox or f.expected_bbox
            if not box:
                reason = {"drawing_alignment": "alignment is a whole-image finding", "zone_correspondence": "zone could not be projected onto the photo"}.get(f.check_type, "no image region could be associated with this finding")
                if f.check_type != "drawing_alignment":
                    self._evidence(st, "finding_crop", f"#{f.seq} {f.subject}", None, "crop", None, finding_id=f.id, error=f"No crop: {reason}.")
                    missing += 1
                continue
            crop, cbox = draw.crop_with_padding(img, box, pad_frac=0.6 if f.check_type in ("device_label", "ferrule_label") else 0.25, min_pad=30)
            if crop.size == 0:
                self._evidence(st, "finding_crop", f"#{f.seq} {f.subject}", None, "crop", None, finding_id=f.id, error="Crop region fell outside the image.")
                missing += 1
                continue
            self._evidence(st, "finding_crop", f"#{f.seq} {f.subject} — original pixels", crop, "crop", "original-frame crop", finding_id=f.id, bbox=cbox, source_asset_id=st.photo_asset.id, fmt="png")
            ann = crop.copy()
            local = [box[0] - cbox[0], box[1] - cbox[1], box[2] - cbox[0], box[3] - cbox[1]]
            if f.expected_bbox and f.bbox:
                e = f.expected_bbox
                draw.box(ann, [e[0] - cbox[0], e[1] - cbox[1], e[2] - cbox[0], e[3] - cbox[1]], (220, 220, 220), None, dashed=True, thickness=2)
            draw.box(ann, local, draw.VERDICT_BGR[f.verdict], None, dashed=f.bbox is None, thickness=2)
            self._evidence(st, "finding_crop_annotated", f"#{f.seq} {f.subject} — annotated", ann, "crop_annotation", "OpenCV annotation", finding_id=f.id, bbox=cbox, fmt="png")
            made += 1
        return {"message": f"{made} findings with image evidence, {missing} without (reason recorded)", "details": {"with_crops": made, "without_crops": missing}}

    def stage_report(self, st: RunState) -> dict:
        from ..reporting.pdf_report import generate_pdf_report

        self.db.flush()
        rep = generate_pdf_report(self.db, st.version.id)
        return {"message": f"PDF report generated ({rep.pages} pages, {rep.size_bytes // 1024} KB)", "details": {"report_id": rep.id, "pages": rep.pages}}


def dedupe_observations(obs: list[dict]) -> list[dict]:
    """Merge overlapping readings of the same text region: keep the highest-confidence reading and
    retain the others as alternatives (so no observation is silently discarded)."""
    def iou(a, b):
        x0, y0, x1, y1 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
        inter = max(0, x1 - x0) * max(0, y1 - y0)
        ua = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
        smaller = min((a[2] - a[0]) * (a[3] - a[1]), (b[2] - b[0]) * (b[3] - b[1]))
        return inter / ua if ua > 0 else 0.0, inter / smaller if smaller > 0 else 0.0

    # crop readings are made at higher resolution; prefer them when overlapping a full-image reading
    order = sorted(obs, key=lambda o: (o["region"] != "full", o["conf"]), reverse=True)
    kept: list[dict] = []
    for o in order:
        dup = None
        for k in kept:
            i, contain = iou(o["box"], k["box"])
            if i > 0.4 or contain > 0.7:
                dup = k
                break
        if dup is None:
            kept.append(o)
        else:
            dup["alts"] = dup["alts"] + [{"variant": o["variant"], "region": o["region"], "text": o["raw"], "normalized": o["norm"], "confidence": round(o["conf"], 4)}]
    return kept


def run_job(job_id: str) -> None:
    db = SessionLocal()
    try:
        job = db.get(ProcessingJob, job_id)
        if job is None or job.status not in ("queued",):
            return
        PipelineRunner(db, job).run()
    finally:
        db.close()


def create_job(db: Session, version: InspectionVersion) -> ProcessingJob:
    job = ProcessingJob(inspection_id=version.inspection_id, version_id=version.id, status="queued")
    db.add(job)
    db.flush()
    for i, (name, title) in enumerate(STAGES):
        db.add(ProcessingStage(job_id=job.id, name=name, title=title, order=i, status="pending"))
    version.status = "queued"
    db.flush()
    return job
