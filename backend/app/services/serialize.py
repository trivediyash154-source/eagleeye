"""Model → API dict serialisers (shapes match app/schemas/api.py)."""
from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..core.config import get_settings
from ..core.util import iso
from ..models import (
    Detection, EvidenceAsset, Finding, InputAsset, Inspection, InspectionVersion, OcrObservation, ProcessingJob, ReviewDecision,
)
from .common import effective_verdict, review_status


def api_prefix() -> str:
    return f"/api/{get_settings().api_version}"


def asset_out(a: InputAsset) -> dict:
    return {
        "id": a.id, "kind": a.kind, "original_filename": a.original_filename, "content_type": a.content_type, "size_bytes": a.size_bytes,
        "sha256": a.sha256, "analysis": a.analysis or {}, "created_at": iso(a.created_at), "inherited": bool(a.inherited_from_asset_id),
        "download_url": f"{api_prefix()}/assets/{a.id}/file",
    }


def effective_counts(db: Session, version_id: str) -> tuple[dict, int, int]:
    findings = db.scalars(select(Finding).where(Finding.version_id == version_id)).all()
    counts = {"PASS": 0, "FAIL": 0, "UNCERTAIN": 0, "WAIVED": 0}
    reviewed = 0
    for f in findings:
        counts[effective_verdict(f)] = counts.get(effective_verdict(f), 0) + 1
        if f.reviews:
            reviewed += 1
    return counts, reviewed, len(findings)


def version_out(db: Session, v: InspectionVersion) -> dict:
    eff, reviewed, n = effective_counts(db, v.id)
    job_id = db.scalar(select(ProcessingJob.id).where(ProcessingJob.version_id == v.id).order_by(ProcessingJob.created_at.desc()).limit(1))
    return {
        "id": v.id, "inspection_id": v.inspection_id, "version_no": v.version_no, "label": v.label, "parent_version_id": v.parent_version_id,
        "status": v.status, "config": v.config or {}, "summary": v.summary or {}, "effective_summary": eff, "registration": v.registration or {},
        "preprocessing": v.preprocessing or {}, "error": v.error, "created_at": iso(v.created_at), "started_at": iso(v.started_at),
        "completed_at": iso(v.completed_at), "duration_ms": v.duration_ms,
        "assets": [asset_out(a) for a in sorted(v.assets, key=lambda a: a.created_at)], "latest_job_id": job_id,
        "reviewed_count": reviewed, "finding_count": n,
    }


def inspection_out(db: Session, i: Inspection, with_versions: bool = False) -> dict:
    versions = sorted(i.versions, key=lambda v: v.version_no)
    out = {
        "id": i.id, "code": i.code, "title": i.title, "cabinet_id": i.cabinet_id, "site": i.site, "reference": i.reference, "inspector": i.inspector,
        "project_ref": i.project_ref, "notes": i.notes, "is_demo": i.is_demo, "created_at": iso(i.created_at), "updated_at": iso(i.updated_at),
        "version_count": len(versions), "latest_version": version_out(db, versions[-1]) if versions else None,
    }
    if with_versions:
        out["versions"] = [version_out(db, v) for v in versions]
    return out


def job_out(j: ProcessingJob) -> dict:
    return {
        "id": j.id, "inspection_id": j.inspection_id, "version_id": j.version_id, "status": j.status, "cancel_requested": bool(j.cancel_requested),
        "current_stage": j.current_stage, "error": j.error, "created_at": iso(j.created_at), "started_at": iso(j.started_at), "finished_at": iso(j.finished_at),
        "stages": [{
            "name": s.name, "title": s.title, "order": s.order, "status": s.status, "message": s.message, "details": s.details or {},
            "started_at": iso(s.started_at), "finished_at": iso(s.finished_at), "duration_ms": s.duration_ms,
        } for s in sorted(j.stages, key=lambda s: s.order)],
    }


def review_out(r: ReviewDecision) -> dict:
    return {
        "id": r.id, "finding_id": r.finding_id, "action": r.action, "resulting_verdict": r.resulting_verdict, "corrected_value": r.corrected_value,
        "reason": r.reason, "notes": r.notes, "reviewer": r.reviewer, "reviewer_kind": r.reviewer_kind, "details": r.details or {}, "created_at": iso(r.created_at),
    }


def evidence_out(e: EvidenceAsset) -> dict:
    url = f"{api_prefix()}/evidence/{e.id}/file" if e.storage_key else None
    return {
        "id": e.id, "inspection_id": e.inspection_id, "version_id": e.version_id, "finding_id": e.finding_id, "kind": e.kind, "title": e.title,
        "content_type": e.content_type, "width": e.width, "height": e.height, "sha256": e.sha256, "bbox": e.bbox, "source_asset_id": e.source_asset_id,
        "operation": e.operation, "algorithm": e.algorithm, "error": e.error, "created_at": iso(e.created_at), "url": url,
        "thumbnail_url": f"{url}?thumb=1" if url and (e.content_type or "").startswith("image/") else None,
    }


def finding_out(f: Finding, version_no: int | None = None) -> dict:
    return {
        "id": f.id, "inspection_id": f.inspection_id, "version_id": f.version_id, "version_no": version_no, "seq": f.seq, "finding_key": f.finding_key,
        "check_type": f.check_type, "zone_code": f.zone_code, "subject": f.subject, "expected_value": f.expected_value, "observed_value": f.observed_value,
        "observed_raw": f.observed_raw, "verdict": f.verdict, "effective_verdict": effective_verdict(f), "review_status": review_status(f), "rule": f.rule,
        "explanation": f.explanation, "confidences": f.confidences or {}, "review_reasons": f.review_reasons or [], "bbox": f.bbox, "expected_bbox": f.expected_bbox,
        "drawing_bbox": f.drawing_bbox, "detection_id": f.detection_id, "ocr_observation_id": f.ocr_observation_id, "model_refs": f.model_refs or {},
        "created_at": iso(f.created_at), "review_count": len(f.reviews or []),
    }


def detection_out(d: Detection) -> dict:
    return {"id": d.id, "class_id": d.class_id, "class_name": d.class_name, "confidence": d.confidence, "above_threshold": d.above_threshold,
            "bbox": [d.x0, d.y0, d.x1, d.y1], "source": d.source, "model_name": d.model_name}


def ocr_out(o: OcrObservation) -> dict:
    return {"id": o.id, "raw_text": o.raw_text, "normalized_text": o.normalized_text, "normalization_steps": o.normalization_steps, "confidence": o.confidence,
            "polygon": o.polygon, "bbox": [o.x0, o.y0, o.x1, o.y1], "region": o.region, "variant": o.variant, "alternatives": o.alternatives,
            "engine": o.engine, "detection_id": o.detection_id}


def finding_detail(db: Session, f: Finding) -> dict:
    v = db.get(InspectionVersion, f.version_id)
    out = finding_out(f, v.version_no if v else None)
    out["details"] = f.details or {}
    out["reviews"] = [review_out(r) for r in f.reviews]
    out["evidence"] = [evidence_out(e) for e in db.scalars(select(EvidenceAsset).where(EvidenceAsset.finding_id == f.id).order_by(EvidenceAsset.created_at))]
    det = db.get(Detection, f.detection_id) if f.detection_id else None
    ocr = db.get(OcrObservation, f.ocr_observation_id) if f.ocr_observation_id else None
    out["detection"] = detection_out(det) if det else None
    out["ocr_observation"] = ocr_out(ocr) if ocr else None
    hist = []
    rows = db.execute(
        select(Finding, InspectionVersion.version_no).join(InspectionVersion, InspectionVersion.id == Finding.version_id)
        .where(Finding.inspection_id == f.inspection_id, Finding.finding_key == f.finding_key, Finding.id != f.id).order_by(InspectionVersion.version_no)
    ).all()
    for g, vno in rows:
        hist.append({"finding_id": g.id, "version_no": vno, "verdict": g.verdict, "effective_verdict": effective_verdict(g), "observed_value": g.observed_value, "created_at": iso(g.created_at)})
    out["history"] = hist
    return out


def counts_by_verdict(db: Session, version_id: str) -> dict:
    rows = db.execute(select(Finding.verdict, func.count()).where(Finding.version_id == version_id).group_by(Finding.verdict)).all()
    return {v: c for v, c in rows}
