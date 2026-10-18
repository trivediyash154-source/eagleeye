from __future__ import annotations

import cv2
import numpy as np
from fastapi import APIRouter, Depends, Query
from fastapi.responses import FileResponse, Response
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from ..core.db import get_db
from ..core.errors import bad_request, conflict, not_found
from ..cv.preprocess import encode_jpeg, thumbnail
from ..inspection.matching import compare
from ..models import EvidenceAsset, Finding, InputAsset, Inspection, InspectionVersion, Report, ReviewDecision
from ..reporting.exports import build_export
from ..reporting.pdf_report import generate_pdf_report
from ..schemas.api import FindingDetail, FindingList, ReviewIn, ReviewOut
from ..services import analytics as an
from ..services.common import VERDICT_ACTIONS, audit, effective_verdict, review_status, reviewer
from ..services.inspections import get_version
from ..services.serialize import evidence_out, finding_detail, finding_out, review_out
from ..storage.local import StorageError, get_storage

router = APIRouter(tags=["findings"])


@router.get("/versions/{version_id}/findings", response_model=FindingList, summary="Findings of a version with filters")
def list_findings(version_id: str, verdict: str | None = None, effective: str | None = None, check_type: str | None = None, zone: str | None = None,
                  review: str | None = Query(None, pattern="^(reviewed|unreviewed)$"), q: str | None = None, db: Session = Depends(get_db)):
    v = get_version(db, version_id)
    rows = db.scalars(select(Finding).options(selectinload(Finding.reviews)).where(Finding.version_id == v.id).order_by(Finding.seq)).all()
    counts = {"PASS": 0, "FAIL": 0, "UNCERTAIN": 0}
    for f in rows:
        counts[f.verdict] += 1
    out = []
    for f in rows:
        if verdict and f.verdict != verdict.upper():
            continue
        if effective and effective_verdict(f) != effective.upper():
            continue
        if check_type and f.check_type != check_type:
            continue
        if zone and (f.zone_code or "") != zone:
            continue
        if review and review_status(f) != review:
            continue
        if q:
            hay = " ".join(str(x or "") for x in (f.subject, f.expected_value, f.observed_value, f.observed_raw, f.check_type, f.zone_code, f.rule)).lower()
            if q.lower() not in hay:
                continue
        out.append(finding_out(f, v.version_no))
    return {"items": out, "total": len(out), "counts": counts}


@router.get("/findings/{finding_id}", response_model=FindingDetail)
def get_finding(finding_id: str, db: Session = Depends(get_db)):
    f = db.get(Finding, finding_id)
    if not f:
        raise not_found("finding", finding_id)
    return finding_detail(db, f)


@router.post("/findings/{finding_id}/reviews", response_model=ReviewOut, status_code=201, summary="Record a human review decision (machine finding stays unchanged)")
def add_review(finding_id: str, body: ReviewIn, db: Session = Depends(get_db)):
    f = db.get(Finding, finding_id)
    if not f:
        raise not_found("finding", finding_id)
    v = db.get(InspectionVersion, f.version_id)
    if v.status != "completed":
        raise conflict("version_not_completed", "Findings can be reviewed once the run has completed.")
    action = body.action
    resulting = None
    details: dict = {"machine_verdict": f.verdict, "previous_effective_verdict": effective_verdict(f)}
    if action == "confirm":
        if f.verdict == "UNCERTAIN":
            raise bad_request("invalid_action", "An UNCERTAIN finding cannot be confirmed as-is; resolve it as PASS or FAIL.")
        resulting = f.verdict
    elif action in ("resolve_pass", "resolve_fail"):
        if f.verdict != "UNCERTAIN" and not (body.reason or "").strip():
            raise bad_request("reason_required", "Overriding a definitive machine verdict requires a reason.")
        resulting = VERDICT_ACTIONS[action]
    elif action == "false_positive":
        if f.verdict != "FAIL":
            raise bad_request("invalid_action", "Only FAIL findings can be marked as false positives.")
        if not (body.reason or "").strip():
            raise bad_request("reason_required", "A reason is required to mark a false positive.")
        resulting = "PASS"
    elif action == "waive":
        if not (body.reason or "").strip():
            raise bad_request("reason_required", "Waiving a finding requires a mandatory reason.")
        resulting = "WAIVED"
    elif action == "correct_observed":
        if not (body.corrected_value or "").strip():
            raise bad_request("value_required", "Provide the corrected observed value.")
        if f.check_type not in ("device_label", "ferrule_label") or not f.expected_value:
            raise bad_request("invalid_action", "Observed-value correction applies to device-label and ferrule findings.")
        cmp_ = compare(f.expected_value, body.corrected_value)
        resulting = "PASS" if cmp_.distance == 0 else "FAIL"
        details["comparison_with_corrected_value"] = cmp_.to_json()
        details["rule"] = "human_reading: exact match → PASS, any difference → FAIL (the inspector's reading replaces OCR for this decision)"
    db.add(ReviewDecision(finding_id=f.id, action=action, resulting_verdict=resulting, corrected_value=(body.corrected_value or None), reason=body.reason, notes=body.notes,
                          reviewer=reviewer(), reviewer_kind="local-demo-identity", details=details))
    audit(db, "review_recorded", "finding", f.id, f.inspection_id, {"action": action, "resulting_verdict": resulting, "seq": f.seq, "version_no": v.version_no}, actor=reviewer())
    db.commit()
    db.refresh(f)
    return review_out(f.reviews[-1])


# --- evidence ----------------------------------------------------------------------

@router.get("/evidence", summary="Browse evidence assets")
def list_evidence(inspection_id: str | None = None, version_id: str | None = None, kind: str | None = None, finding_id: str | None = None,
                  page: int = Query(1, ge=1), page_size: int = Query(60, ge=1, le=200), db: Session = Depends(get_db)):
    stmt = select(EvidenceAsset)
    if inspection_id:
        stmt = stmt.where(EvidenceAsset.inspection_id == inspection_id)
    if version_id:
        stmt = stmt.where(EvidenceAsset.version_id == version_id)
    if kind:
        stmt = stmt.where(EvidenceAsset.kind.in_(kind.split(",")))
    if finding_id:
        stmt = stmt.where(EvidenceAsset.finding_id == finding_id)
    rows = db.scalars(stmt.order_by(EvidenceAsset.created_at.desc())).all()
    total = len(rows)
    rows = rows[(page - 1) * page_size: page * page_size]
    fmap = {f.id: f for f in db.scalars(select(Finding).where(Finding.id.in_([r.finding_id for r in rows if r.finding_id])))} if rows else {}
    imap = {}
    out = []
    for e in rows:
        if e.inspection_id not in imap:
            imap[e.inspection_id] = db.get(Inspection, e.inspection_id)
        vno = db.scalar(select(InspectionVersion.version_no).where(InspectionVersion.id == e.version_id))
        f = fmap.get(e.finding_id)
        out.append({**evidence_out(e), "inspection_code": imap[e.inspection_id].code, "is_demo": imap[e.inspection_id].is_demo, "version_no": vno,
                    "finding": {"seq": f.seq, "check_type": f.check_type, "subject": f.subject, "verdict": f.verdict} if f else None})
    return {"items": out, "total": total, "page": page, "page_size": page_size}


def _file_response(key: str, content_type: str, filename: str, download: bool):
    try:
        path = get_storage().path_for(key)
    except StorageError as exc:
        raise not_found("file", key) from exc
    if not path.is_file():
        raise not_found("file", filename)
    return FileResponse(path, media_type=content_type, filename=filename if download else None,
                        headers={"Cache-Control": "private, max-age=86400", "X-Content-Type-Options": "nosniff"})


@router.get("/evidence/{evidence_id}/file", summary="Download/stream an evidence image (thumb=1 for a thumbnail)")
def evidence_file(evidence_id: str, thumb: bool = False, download: bool = False, db: Session = Depends(get_db)):
    e = db.get(EvidenceAsset, evidence_id)
    if not e or not e.storage_key:
        raise not_found("evidence file", evidence_id)
    if thumb and (e.content_type or "").startswith("image/"):
        st = get_storage()
        tkey = e.storage_key.rsplit(".", 1)[0] + ".thumb.jpg"
        if not st.exists(tkey):
            img = cv2.imdecode(np.frombuffer(st.read_bytes(e.storage_key), np.uint8), cv2.IMREAD_COLOR)
            if img is None:
                raise not_found("image", evidence_id)
            st.put_bytes(tkey, encode_jpeg(thumbnail(img, 480), 82))
        return _file_response(tkey, "image/jpeg", "thumb.jpg", False)
    ext = (e.content_type or "application/octet-stream").split("/")[-1].replace("jpeg", "jpg")
    return _file_response(e.storage_key, e.content_type or "application/octet-stream", f"{e.kind}_{e.id}.{ext}", download)


@router.get("/assets/{asset_id}/file", summary="Download an uploaded input file")
def asset_file(asset_id: str, download: bool = False, db: Session = Depends(get_db)):
    a = db.get(InputAsset, asset_id)
    if not a:
        raise not_found("asset", asset_id)
    return _file_response(a.storage_key, a.content_type, a.original_filename, download)


# --- reports -------------------------------------------------------------------------

def _report_out(r: Report) -> dict:
    from ..core.util import iso

    return {"id": r.id, "inspection_id": r.inspection_id, "version_id": r.version_id, "format": r.format, "filename": r.filename, "size_bytes": r.size_bytes,
            "sha256": r.sha256, "pages": r.pages, "created_at": iso(r.created_at), "download_url": f"/api/v1/reports/{r.id}/download"}


@router.post("/versions/{version_id}/reports", status_code=201, summary="Generate a report/export: pdf | json | csv | xlsx")
def create_report(version_id: str, body: dict, db: Session = Depends(get_db)):
    v = get_version(db, version_id)
    fmt = (body or {}).get("format", "pdf")
    if v.status != "completed":
        raise conflict("version_not_completed", "Reports can be generated for completed versions only.")
    if fmt not in ("pdf", "json", "csv", "xlsx"):
        raise bad_request("invalid_format", "format must be pdf, json, csv or xlsx")
    rep = generate_pdf_report(db, v.id) if fmt == "pdf" else build_export(db, v.id, fmt)
    db.commit()
    return _report_out(rep)


@router.get("/reports", summary="List generated reports")
def list_reports(inspection_id: str | None = None, version_id: str | None = None, limit: int = Query(100, ge=1, le=500), db: Session = Depends(get_db)):
    stmt = select(Report).order_by(Report.created_at.desc()).limit(limit)
    if inspection_id:
        stmt = stmt.where(Report.inspection_id == inspection_id)
    if version_id:
        stmt = stmt.where(Report.version_id == version_id)
    out = []
    for r in db.scalars(stmt):
        insp = db.get(Inspection, r.inspection_id)
        vno = db.scalar(select(InspectionVersion.version_no).where(InspectionVersion.id == r.version_id))
        out.append({**_report_out(r), "inspection_code": insp.code, "cabinet_id": insp.cabinet_id, "is_demo": insp.is_demo, "version_no": vno})
    return {"items": out}


@router.get("/reports/{report_id}/download")
def download_report(report_id: str, db: Session = Depends(get_db)):
    r = db.get(Report, report_id)
    if not r:
        raise not_found("report", report_id)
    ctype = {"pdf": "application/pdf", "json": "application/json", "csv": "text/csv", "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}[r.format]
    return _file_response(r.storage_key, ctype, r.filename, True)


# --- analytics & review queue --------------------------------------------------------

@router.get("/analytics/overview", summary="KPIs and distributions computed from persisted records")
def analytics_overview(dataset: str = Query("all", pattern="^(all|real|demo)$"), date_from: str | None = None, date_to: str | None = None, db: Session = Depends(get_db)):
    try:
        return an.overview(db, dataset, date_from, date_to)
    except ValueError as exc:
        raise bad_request("invalid_date", str(exc)) from exc


@router.get("/analytics/activity", summary="Recent activity feed")
def analytics_activity(limit: int = Query(20, ge=1, le=100), dataset: str = Query("all", pattern="^(all|real|demo)$"), db: Session = Depends(get_db)):
    return {"items": an.activity(db, limit, dataset)}


@router.get("/review-queue", summary="Findings needing human review, with reasons")
def review_queue(inspection_id: str | None = None, reason: str | None = None, check_type: str | None = None,
                 sort: str = Query("tier", pattern="^(tier|newest|inspection)$"), dataset: str = Query("all", pattern="^(all|real|demo)$"), db: Session = Depends(get_db)):
    return an.review_queue(db, inspection_id, reason, check_type, sort, dataset)
