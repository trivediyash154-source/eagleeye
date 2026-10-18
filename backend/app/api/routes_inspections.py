from __future__ import annotations

from fastapi import APIRouter, Depends, File, Form, Query, UploadFile
from fastapi.responses import Response
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from ..core.db import get_db
from ..core.errors import bad_request, conflict, not_found
from ..core.util import as_aware
from ..cv.detector import get_detector
from ..cv.preprocess import encode_png
from ..cv.registration import project_bbox
from ..drawing.pdf_parser import PdfError, render_page
from ..inspection.comparison import CATEGORY_INFO, compare_versions
from ..inspection.pipeline import ALL_CHECKS, create_job, merged_config
from ..inspection.spreadsheet import SheetError, parse_records
from ..models import (
    AuditEvent, Detection, Drawing, DrawingZone, EvidenceAsset, ExpectedComponent, ExpectedIdentifier, Finding, InputAsset, Inspection,
    InspectionVersion, OcrObservation, ProcessingJob, VersionComparison,
)
from ..ocr.engines import get_ocr
from ..schemas.api import (
    AssetOut, InspectionCreate, InspectionDetail, InspectionList, InspectionUpdate, JobOut, ManualAlignmentIn, Readiness, VersionConfigUpdate, VersionOut, ZonesUpdate,
)
from ..services import inspections as svc
from ..services.common import audit, effective_verdict, reviewer
from ..services.serialize import asset_out, detection_out, evidence_out, inspection_out, job_out, ocr_out, version_out
from ..storage.local import get_storage
from ..workers.jobs import submit

router = APIRouter(tags=["inspections"])


@router.post("/inspections", response_model=InspectionDetail, status_code=201, summary="Create an inspection case (version 1 in draft)")
def create_inspection(body: InspectionCreate, db: Session = Depends(get_db)):
    insp = svc.create_inspection(db, body.model_dump())
    db.commit()
    db.refresh(insp)
    return inspection_out(db, insp, with_versions=True)


@router.get("/inspections", response_model=InspectionList, summary="List inspections with search, filters, sorting and pagination")
def list_inspections(
    q: str | None = None, dataset: str = Query("all", pattern="^(all|real|demo)$"), status: str | None = None, verdict: str | None = None,
    date_from: str | None = None, date_to: str | None = None, sort: str = Query("created_at", pattern="^(created_at|code|cabinet_id|title|status)$"),
    order: str = Query("desc", pattern="^(asc|desc)$"), page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100), db: Session = Depends(get_db),
):
    stmt = select(Inspection)
    if q:
        like = f"%{q.strip()}%"
        stmt = stmt.where(or_(Inspection.code.ilike(like), Inspection.title.ilike(like), Inspection.cabinet_id.ilike(like), Inspection.site.ilike(like), Inspection.reference.ilike(like)))
    if dataset == "real":
        stmt = stmt.where(Inspection.is_demo.is_(False))
    elif dataset == "demo":
        stmt = stmt.where(Inspection.is_demo.is_(True))
    items = db.scalars(stmt).all()
    from datetime import datetime, timedelta, timezone

    def _d(s, end=False):
        d = datetime.fromisoformat(s)
        d = d if d.tzinfo else d.replace(tzinfo=timezone.utc)
        return d + timedelta(days=1) if end and len(s) <= 10 else d

    if date_from:
        items = [i for i in items if as_aware(i.created_at) >= _d(date_from)]
    if date_to:
        items = [i for i in items if as_aware(i.created_at) < _d(date_to, True)]

    def latest(i):
        return max(i.versions, key=lambda v: v.version_no) if i.versions else None

    if status:
        items = [i for i in items if latest(i) and latest(i).status == status]
    if verdict:
        verdict = verdict.upper()

        def has(i):
            lv = latest(i)
            if not lv:
                return False
            if verdict == "NEEDS_REVIEW":
                return any(effective_verdict(f) == "UNCERTAIN" or (f.verdict == "FAIL" and not f.reviews) for f in db.scalars(select(Finding).where(Finding.version_id == lv.id)))
            return any(effective_verdict(f) == verdict for f in db.scalars(select(Finding).where(Finding.version_id == lv.id)))

        items = [i for i in items if has(i)]
    key = {"created_at": lambda i: as_aware(i.created_at), "code": lambda i: i.code, "cabinet_id": lambda i: i.cabinet_id.lower(), "title": lambda i: i.title.lower(),
           "status": lambda i: latest(i).status if latest(i) else ""}[sort]
    items.sort(key=key, reverse=order == "desc")
    total = len(items)
    page_items = items[(page - 1) * page_size: page * page_size]
    return {"items": [inspection_out(db, i) for i in page_items], "total": total, "page": page, "page_size": page_size}


@router.get("/inspections/{inspection_id}", response_model=InspectionDetail)
def get_inspection(inspection_id: str, db: Session = Depends(get_db)):
    return inspection_out(db, svc.get_inspection(db, inspection_id), with_versions=True)


@router.patch("/inspections/{inspection_id}", response_model=InspectionDetail)
def update_inspection(inspection_id: str, body: InspectionUpdate, db: Session = Depends(get_db)):
    insp = svc.get_inspection(db, inspection_id)
    changes = body.model_dump(exclude_unset=True)
    for k, val in changes.items():
        setattr(insp, k, val)
    audit(db, "inspection_updated", "inspection", insp.id, insp.id, {"fields": sorted(changes)}, actor=reviewer())
    db.commit()
    return inspection_out(db, insp, with_versions=True)


@router.get("/inspections/{inspection_id}/timeline", summary="Audit trail for the inspection")
def timeline(inspection_id: str, db: Session = Depends(get_db)):
    insp = svc.get_inspection(db, inspection_id)
    evs = db.scalars(select(AuditEvent).where(AuditEvent.inspection_id == insp.id).order_by(AuditEvent.created_at)).all()
    from ..core.util import iso

    return {"items": [{"id": e.id, "created_at": iso(e.created_at), "actor": e.actor, "event_type": e.event_type, "entity_type": e.entity_type,
                       "entity_id": e.entity_id, "details": e.details, "message": e.message} for e in evs]}


@router.post("/inspections/{inspection_id}/reinspect", response_model=VersionOut, status_code=201, summary="Create a new version; earlier versions stay intact")
async def reinspect(inspection_id: str, label: str | None = Form(default=None), reuse_photo: bool = Form(default=False),
                    photo: UploadFile | None = File(default=None), db: Session = Depends(get_db)):
    insp = svc.get_inspection(db, inspection_id)
    nv = svc.create_reinspection(db, insp, label, reuse_photo or photo is None)
    if photo is not None:
        svc.store_asset(db, nv, "photo", photo.filename or "photo.jpg", await photo.read())
    db.commit()
    db.refresh(nv)
    return version_out(db, nv)


@router.get("/inspections/{inspection_id}/compare", summary="Compare two versions by stable finding keys")
def compare(inspection_id: str, from_version: int | None = None, to_version: int | None = None, db: Session = Depends(get_db)):
    insp = svc.get_inspection(db, inspection_id)
    vs = {v.version_no: v for v in insp.versions}
    done = sorted(n for n, v in vs.items() if v.status == "completed")
    if len(done) < 2 and (from_version is None or to_version is None):
        raise conflict("not_enough_versions", "At least two completed versions are required for a comparison.")
    to_v = vs.get(to_version or done[-1])
    from_v = vs.get(from_version or (to_v.version_no - 1 if to_v and (to_v.version_no - 1) in done else done[-2]))
    if not from_v or not to_v or from_v.status != "completed" or to_v.status != "completed":
        raise bad_request("invalid_versions", "Both versions must exist and be completed.")
    cmp_ = db.scalar(select(VersionComparison).where(VersionComparison.from_version_id == from_v.id, VersionComparison.to_version_id == to_v.id))
    if cmp_ is None or any(f.reviews and f.reviews[-1].created_at > cmp_.created_at for f in db.scalars(select(Finding).where(Finding.version_id == from_v.id))):
        cmp_ = compare_versions(db, from_v.id, to_v.id)
        db.commit()
    from ..core.util import iso

    return {"id": cmp_.id, "from_version": from_v.version_no, "to_version": to_v.version_no, "from_version_id": from_v.id, "to_version_id": to_v.id,
            "summary": cmp_.summary, "items": cmp_.items, "categories": CATEGORY_INFO, "created_at": iso(cmp_.created_at)}


# --- versions -------------------------------------------------------------------

@router.get("/versions/{version_id}", response_model=VersionOut)
def get_version(version_id: str, db: Session = Depends(get_db)):
    return version_out(db, svc.get_version(db, version_id))


@router.patch("/versions/{version_id}/config", response_model=VersionOut, summary="Update checks, page, sheet mapping and thresholds of a draft version")
def update_config(version_id: str, body: VersionConfigUpdate, db: Session = Depends(get_db)):
    v = svc.get_version(db, version_id)
    svc.require_editable(v)
    cfg = merged_config(v.config)
    upd = body.model_dump(exclude_unset=True)
    if "checks" in upd:
        bad = [c for c in upd["checks"] or [] if c not in ALL_CHECKS]
        if bad:
            raise bad_request("invalid_checks", f"Unknown checks: {bad}")
        if not upd["checks"]:
            raise bad_request("no_checks", "Select at least one check.")
    for k, val in upd.items():
        if isinstance(val, dict) and isinstance(cfg.get(k), dict):
            cfg[k] = {**cfg[k], **val}
        else:
            cfg[k] = val
    v.config = cfg
    audit(db, "config_updated", "version", v.id, v.inspection_id, {"fields": sorted(upd)}, actor=reviewer())
    db.commit()
    return version_out(db, v)


@router.post("/versions/{version_id}/assets", response_model=AssetOut, status_code=201, summary="Upload (or replace) the photo, GA drawing or expected list")
async def upload_asset(version_id: str, kind: str = Form(...), file: UploadFile = File(...), db: Session = Depends(get_db)):
    v = svc.get_version(db, version_id)
    svc.require_editable(v)
    data = await file.read()
    asset = svc.store_asset(db, v, kind, file.filename or "upload", data)
    if kind == "drawing":
        pages = (asset.analysis or {}).get("page_count", 1)
        cfg = merged_config(v.config)
        if cfg.get("drawing_page", 0) >= pages:
            cfg["drawing_page"] = 0
            v.config = cfg
    db.commit()
    return asset_out(asset)


@router.delete("/versions/{version_id}/assets/{asset_id}", status_code=204)
def delete_asset(version_id: str, asset_id: str, db: Session = Depends(get_db)):
    v = svc.get_version(db, version_id)
    svc.require_editable(v)
    a = db.get(InputAsset, asset_id)
    if not a or a.version_id != v.id:
        raise not_found("asset", asset_id)
    audit(db, "asset_removed", "asset", a.id, v.inspection_id, {"kind": a.kind, "filename": a.original_filename}, actor=reviewer())
    db.delete(a)
    db.commit()
    return Response(status_code=204)


@router.get("/versions/{version_id}/readiness", response_model=Readiness, summary="Pre-run validation of inputs, models and storage")
def readiness(version_id: str, db: Session = Depends(get_db)):
    v = svc.get_version(db, version_id)
    cfg = merged_config(v.config)
    items = []

    def add(key, label, status, message):
        items.append({"key": key, "label": label, "status": status, "message": message})

    by = {a.kind: a for a in v.assets}
    st = get_storage()
    photo = by.get("photo")
    if not photo:
        add("photo", "Cabinet photograph", "error", "No photograph uploaded.")
    elif not st.exists(photo.storage_key):
        add("photo", "Cabinet photograph", "error", "Stored photo file is missing.")
    else:
        q = (photo.analysis or {}).get("quality", {})
        warns = q.get("warnings", [])
        add("photo", "Cabinet photograph", "warning" if warns else "ok",
            f"{photo.original_filename}: {q.get('width')}×{q.get('height')}px, quality {q.get('rating')}" + (f" — {warns[0]['message']}" if warns else ""))
    drw = by.get("drawing")
    if not drw:
        add("drawing", "GA drawing", "warning", "No GA drawing: registration and position-based checks will be UNCERTAIN.")
    else:
        an = drw.analysis or {}
        pc = an.get("page_count", 0)
        page = cfg.get("drawing_page", 0)
        if page >= pc:
            add("drawing_page", "Drawing page", "error", f"Selected page {page + 1} does not exist ({pc} pages).")
        else:
            pinfo = (an.get("pages") or [{}])[page]
            add("drawing", "GA drawing", "warning" if pinfo.get("kind") in ("raster", "empty") else "ok",
                f"{drw.original_filename}: page {page + 1}/{pc}, {pinfo.get('kind')} content, {pinfo.get('words', 0)} text words")
    lst = by.get("expected_list")
    if not lst:
        add("expected_list", "Expected component / wire list", "error", "No expected list uploaded.")
    else:
        try:
            parsed = parse_records(st.read_bytes(lst.storage_key), lst.original_filename, cfg.get("sheets"))
            n_c, n_i = len(parsed["components"]), len(parsed["identifiers"])
            if n_c + n_i == 0:
                add("expected_list", "Expected component / wire list", "error", "No records parsed — check sheet selection and column mapping.")
            else:
                add("expected_list", "Expected component / wire list", "warning" if parsed["warnings"] else "ok",
                    f"{n_c} components, {n_i} wire/ferrule records" + (f"; {len(parsed['warnings'])} warning(s): {parsed['warnings'][0]['message']}" if parsed["warnings"] else ""))
        except SheetError as exc:
            add("expected_list", "Expected component / wire list", "error", str(exc))
    det = get_detector()
    if not det.load():
        add("detector", "YOLOv8 detector", "warning", f"Unavailable: {det.last_error}")
    elif det.kind == "generic_coco":
        add("detector", "YOLOv8 detector", "warning", f"{det.model_name}: generic COCO classes only — component presence/type will be UNCERTAIN.")
    else:
        add("detector", "YOLOv8 detector", "ok", f"{det.model_name} on {det.device}; classes: {', '.join(sorted(det.supported_cabinet_classes))}")
    ocr = get_ocr()
    if ocr.load():
        add("ocr", "OCR engine", "ok", f"{ocr.engine.name} {getattr(ocr.engine, 'version', '')}" + (f" (PaddleOCR unavailable: {ocr.engine_errors.get('paddle')})" if ocr.engine_errors.get("paddle") else ""))
    else:
        add("ocr", "OCR engine", "warning", f"Unavailable: {ocr.last_error}")
    ok, msg = st.writable()
    add("storage", "Output storage", "ok" if ok else "error", "Writable" if ok else msg)
    checks = cfg.get("checks") or []
    add("checks", "Selected checks", "ok" if checks else "error", ", ".join(checks) if checks else "No checks selected.")
    if v.status not in svc.EDITABLE:
        add("version", "Version state", "error", f"Version is '{v.status}' and cannot be run again; create a reinspection.")
    return {"ready": not any(i["status"] == "error" for i in items), "items": items}


@router.post("/versions/{version_id}/run", response_model=JobOut, status_code=202, summary="Start the inspection pipeline for a version")
def run_version(version_id: str, db: Session = Depends(get_db)):
    v = svc.get_version(db, version_id)
    active = db.scalar(select(ProcessingJob).where(ProcessingJob.version_id == v.id, ProcessingJob.status.in_(["queued", "running"])))
    if active:
        raise conflict("already_running", "A job for this version is already queued or running.", {"job_id": active.id})
    svc.require_editable(v)
    r = readiness(version_id, db)
    if not r["ready"]:
        raise bad_request("not_ready", "Inputs are not ready for processing.", [i for i in r["items"] if i["status"] == "error"])
    job = create_job(db, v)
    db.commit()
    submit(job.id)
    db.refresh(job)
    return job_out(job)


@router.get("/versions/{version_id}/media", summary="Key images for a version (original, annotated, overlays, drawing render)")
def version_media(version_id: str, db: Session = Depends(get_db)):
    v = svc.get_version(db, version_id)
    evs = db.scalars(select(EvidenceAsset).where(EvidenceAsset.version_id == v.id, EvidenceAsset.finding_id.is_(None))).all()
    out = {e.kind: evidence_out(e) for e in evs}
    photo = next((a for a in v.assets if a.kind == "photo"), None)
    return {"version_id": v.id, "items": out, "input_photo": asset_out(photo) if photo else None}


@router.get("/versions/{version_id}/detections")
def version_detections(version_id: str, include_low: bool = False, db: Session = Depends(get_db)):
    v = svc.get_version(db, version_id)
    stmt = select(Detection).where(Detection.version_id == v.id)
    if not include_low:
        stmt = stmt.where(Detection.above_threshold.is_(True))
    rows = db.scalars(stmt.order_by(Detection.class_name, Detection.confidence.desc())).all()
    return {"items": [detection_out(d) for d in rows], "detector": get_detector().status()}


@router.get("/versions/{version_id}/ocr")
def version_ocr(version_id: str, db: Session = Depends(get_db)):
    v = svc.get_version(db, version_id)
    rows = db.scalars(select(OcrObservation).where(OcrObservation.version_id == v.id).order_by(OcrObservation.y0, OcrObservation.x0)).all()
    links = {}
    for f in db.scalars(select(Finding).where(Finding.version_id == v.id, Finding.ocr_observation_id.is_not(None))):
        links.setdefault(f.ocr_observation_id, []).append({"finding_id": f.id, "seq": f.seq, "check_type": f.check_type, "expected_value": f.expected_value,
                                                             "verdict": f.verdict, "effective_verdict": effective_verdict(f), "edit_distance": (f.confidences or {}).get("edit_distance"),
                                                             "review_count": len(f.reviews)})
    return {"items": [{**ocr_out(o), "findings": links.get(o.id, [])} for o in rows]}


@router.get("/versions/{version_id}/expected")
def version_expected(version_id: str, db: Session = Depends(get_db)):
    v = svc.get_version(db, version_id)
    comps = db.scalars(select(ExpectedComponent).where(ExpectedComponent.version_id == v.id).order_by(ExpectedComponent.zone_code, ExpectedComponent.tag)).all()
    ids = db.scalars(select(ExpectedIdentifier).where(ExpectedIdentifier.version_id == v.id).order_by(ExpectedIdentifier.source_row)).all()
    return {
        "components": [{"id": c.id, "tag": c.tag, "zone_code": c.zone_code, "component_type": c.component_type, "canonical_class": c.canonical_class, "expected_label": c.expected_label,
                        "quantity": c.quantity, "notes": c.notes, "source": f"{c.source_sheet} row {c.source_row}", "drawing_bbox": c.drawing_bbox,
                        "drawing_label_bbox": c.drawing_label_bbox, "drawing_match": c.drawing_match} for c in comps],
        "identifiers": [{"id": i.id, "kind": i.kind, "value": i.value, "terminal_ref": i.terminal_ref, "wire_color": i.wire_color, "component_tag": i.component_tag,
                         "zone_code": i.zone_code, "source": f"{i.source_sheet} row {i.source_row}", "drawing_bbox": i.drawing_bbox, "drawing_terminal_bbox": i.drawing_terminal_bbox,
                         "drawing_match": i.drawing_match} for i in ids],
    }


@router.get("/versions/{version_id}/drawing", summary="Parsed drawing, zones, located identifiers and their projection onto the photo")
def version_drawing(version_id: str, db: Session = Depends(get_db)):
    import numpy as np

    v = svc.get_version(db, version_id)
    d = db.scalar(select(Drawing).where(Drawing.version_id == v.id))
    reg = v.registration or {}
    H = np.array(reg["homography"]) if reg.get("usable") and reg.get("homography") else None
    drawing_asset = next((a for a in v.assets if a.kind == "drawing"), None)
    if d is None:
        return {"parsed": False, "asset": asset_out(drawing_asset) if drawing_asset else None, "registration": reg, "zones": [], "components": [], "identifiers": [],
                "message": "The drawing has not been parsed for this version yet (it is parsed when the inspection runs)." if drawing_asset else "No GA drawing uploaded."}
    render = db.scalar(select(EvidenceAsset).where(EvidenceAsset.version_id == v.id, EvidenceAsset.kind == "drawing_page"))

    def proj(b):
        if H is None or not b:
            return None
        return project_bbox(H, b)[1]

    exp = version_expected(version_id, db)
    for c in exp["components"]:
        c["projected_quad"] = proj(c["drawing_bbox"])
    for i in exp["identifiers"]:
        i["projected_quad"] = proj(i["drawing_bbox"])
    return {
        "parsed": True,
        "drawing": {"id": d.id, "page_index": d.page_index, "page_count": d.page_count, "width": d.page_width, "height": d.page_height, "kind": d.content_kind,
                    "render_url": evidence_out(render)["url"] if render else None, "render_scale": d.render_scale, "warnings": d.warnings, "stats": d.stats,
                    "text_spans": d.text_spans[:4000], "coordinate_convention": "PDF points, origin top-left, y downward"},
        "asset": asset_out(drawing_asset) if drawing_asset else None,
        "zones": [{"id": z.id, "code": z.code, "name": z.name, "bbox": [z.x0, z.y0, z.x1, z.y1], "source": z.source, "notes": z.notes, "projected_quad": proj([z.x0, z.y0, z.x1, z.y1])} for z in d.zones],
        "components": exp["components"], "identifiers": exp["identifiers"], "registration": reg,
    }


@router.put("/versions/{version_id}/zones", summary="Correct zone definitions (persisted on the drawing record; applied by the next run)")
def update_zones(version_id: str, body: ZonesUpdate, db: Session = Depends(get_db)):
    v = svc.get_version(db, version_id)
    d = db.scalar(select(Drawing).where(Drawing.version_id == v.id))
    zones = [{"code": z.code.strip().upper(), "name": z.name, "bbox": [min(z.bbox[0], z.bbox[2]), min(z.bbox[1], z.bbox[3]), max(z.bbox[0], z.bbox[2]), max(z.bbox[1], z.bbox[3])]} for z in body.zones]
    if len({z["code"] for z in zones}) != len(zones):
        raise bad_request("duplicate_zone", "Zone codes must be unique.")
    if v.status in svc.EDITABLE:
        cfg = merged_config(v.config)
        cfg["manual_zones"] = zones
        v.config = cfg
    if d is not None:
        before = [{"code": z.code, "bbox": [z.x0, z.y0, z.x1, z.y1], "source": z.source} for z in d.zones]
        for z in list(d.zones):
            db.delete(z)
        db.flush()
        for z in zones:
            b = z["bbox"]
            db.add(DrawingZone(drawing_id=d.id, code=z["code"], name=z["name"], x0=b[0], y0=b[1], x1=b[2], y1=b[3], source="manual", notes="defined/corrected by inspector"))
        audit(db, "zones_corrected", "drawing", d.id, v.inspection_id, {"before": before, "after": zones}, actor=reviewer())
    else:
        audit(db, "zones_defined", "version", v.id, v.inspection_id, {"after": zones}, actor=reviewer())
    db.commit()
    applied = "will be used when this version runs" if v.status in svc.EDITABLE else "saved on the drawing record; run a reinspection to re-verify with them (existing findings are unchanged)"
    return {"saved": len(zones), "message": f"Zone corrections {applied}."}


@router.post("/versions/{version_id}/alignment", summary="Manual anchor alignment; for a completed version this creates a new version")
def manual_alignment(version_id: str, body: ManualAlignmentIn, db: Session = Depends(get_db)):
    v = svc.get_version(db, version_id)
    anchors = [a.model_dump() for a in body.anchors]
    target = v
    if v.status not in svc.EDITABLE:
        insp = svc.get_inspection(db, v.inspection_id)
        target = svc.create_reinspection(db, insp, "Re-run with manual alignment", reuse_photo=True, config_overrides={"manual_anchors": anchors})
    else:
        cfg = merged_config(v.config)
        cfg["manual_anchors"] = anchors
        v.config = cfg
    audit(db, "manual_alignment_set", "version", target.id, v.inspection_id, {"anchors": len(anchors), "source_version": v.version_no}, actor=reviewer())
    db.commit()
    job = None
    if body.rerun:
        job_resp = run_version(target.id, db)
        job = job_resp
    db.refresh(target)
    return {"version": version_out(db, target), "job": job}


@router.get("/assets/{asset_id}/pdf/pages/{page}/preview", summary="Render a PDF page preview (PNG)")
def pdf_preview(asset_id: str, page: int, zoom: float = Query(1.0, ge=0.2, le=3.0), db: Session = Depends(get_db)):
    a = db.get(InputAsset, asset_id)
    if not a or a.kind != "drawing":
        raise not_found("drawing asset", asset_id)
    try:
        img, _ = render_page(get_storage().read_bytes(a.storage_key), page, zoom=zoom, max_side=2600)
    except PdfError as exc:
        raise bad_request("invalid_page", str(exc)) from exc
    return Response(encode_png(img), media_type="image/png", headers={"Cache-Control": "private, max-age=3600"})


@router.post("/assets/{asset_id}/spreadsheet/preview", summary="Parse the expected list with a sheet/column mapping and return records + warnings")
def spreadsheet_preview(asset_id: str, body: dict, db: Session = Depends(get_db)):
    a = db.get(InputAsset, asset_id)
    if not a or a.kind != "expected_list":
        raise not_found("expected list asset", asset_id)
    try:
        res = parse_records(get_storage().read_bytes(a.storage_key), a.original_filename, body.get("sheets"))
    except SheetError as exc:
        raise bad_request("unreadable_spreadsheet", str(exc)) from exc
    return {"components": res["components"][:200], "identifiers": res["identifiers"][:200], "counts": {"components": len(res["components"]), "identifiers": len(res["identifiers"])},
            "warnings": res["warnings"], "sheets": res["sheets"]}


@router.get("/jobs", summary="Active and recent processing jobs")
def list_jobs(active: bool = False, limit: int = Query(20, ge=1, le=100), db: Session = Depends(get_db)):
    stmt = select(ProcessingJob).order_by(ProcessingJob.created_at.desc()).limit(limit)
    if active:
        stmt = select(ProcessingJob).where(ProcessingJob.status.in_(["queued", "running"])).order_by(ProcessingJob.created_at.desc())
    out = []
    for j in db.scalars(stmt):
        insp = db.get(Inspection, j.inspection_id)
        v = db.get(InspectionVersion, j.version_id)
        out.append({**job_out(j), "inspection_code": insp.code if insp else None, "cabinet_id": insp.cabinet_id if insp else None, "version_no": v.version_no if v else None})
    return {"items": out}


@router.get("/jobs/{job_id}", response_model=JobOut)
def get_job(job_id: str, db: Session = Depends(get_db)):
    j = db.get(ProcessingJob, job_id)
    if not j:
        raise not_found("job", job_id)
    return job_out(j)


@router.post("/jobs/{job_id}/cancel", response_model=JobOut, summary="Request cancellation (honoured between stages)")
def cancel_job(job_id: str, db: Session = Depends(get_db)):
    j = db.get(ProcessingJob, job_id)
    if not j:
        raise not_found("job", job_id)
    if j.status not in ("queued", "running"):
        raise conflict("not_cancellable", f"Job is already {j.status}.")
    j.cancel_requested = 1
    if j.status == "queued":
        from ..core.util import utcnow

        j.status = "cancelled"
        j.finished_at = utcnow()
        for s in j.stages:
            s.status, s.message = "skipped", "Cancelled before start"
        v = db.get(InspectionVersion, j.version_id)
        v.status = "cancelled"
    audit(db, "cancel_requested", "job", j.id, j.inspection_id, {}, actor=reviewer())
    db.commit()
    return job_out(j)


@router.get("/stats/counts", include_in_schema=False)
def _counts(db: Session = Depends(get_db)):
    return {"inspections": db.scalar(select(func.count()).select_from(Inspection)), "findings": db.scalar(select(func.count()).select_from(Finding))}
