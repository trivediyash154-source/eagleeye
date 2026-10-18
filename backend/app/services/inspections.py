from __future__ import annotations

import re

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.config import get_settings
from ..core.errors import ApiError, bad_request, conflict, not_found
from ..cv.preprocess import ImageDecodeError, assess_quality, decode_image
from ..drawing.pdf_parser import PdfError, inspect_pdf
from ..inspection.pipeline import DEFAULT_CONFIG, merged_config
from ..inspection.spreadsheet import SheetError, analyze_workbook
from ..models import Drawing, InputAsset, Inspection, InspectionVersion
from ..storage.local import get_storage
from .common import audit, reviewer

EDITABLE = {"draft", "failed", "cancelled"}
KINDS = {"photo", "drawing", "expected_list"}


def next_code(db: Session) -> str:
    codes = db.scalars(select(Inspection.code)).all()
    nums = [int(m.group(1)) for c in codes if (m := re.match(r"EYE-(\d+)$", c or ""))]
    return f"EYE-{(max(nums) + 1) if nums else 1:04d}"


def create_inspection(db: Session, data: dict, is_demo: bool = False) -> Inspection:
    insp = Inspection(code=next_code(db), is_demo=is_demo, **data)
    db.add(insp)
    db.flush()
    v = InspectionVersion(inspection_id=insp.id, version_no=1, label="Initial inspection", status="draft", config=dict(DEFAULT_CONFIG))
    db.add(v)
    db.flush()
    audit(db, "inspection_created", "inspection", insp.id, insp.id, {"code": insp.code, "cabinet_id": insp.cabinet_id, "demo": is_demo}, actor=reviewer())
    return insp


def get_inspection(db: Session, inspection_id: str) -> Inspection:
    insp = db.get(Inspection, inspection_id) or db.scalar(select(Inspection).where(Inspection.code == inspection_id))
    if not insp:
        raise not_found("inspection", inspection_id)
    return insp


def get_version(db: Session, version_id: str) -> InspectionVersion:
    v = db.get(InspectionVersion, version_id)
    if not v:
        raise not_found("version", version_id)
    return v


def require_editable(v: InspectionVersion) -> None:
    if v.status not in EDITABLE:
        raise conflict("version_immutable", f"Version {v.version_no} is '{v.status}'. Completed versions are immutable; create a reinspection instead.")


def _sniff(kind: str, filename: str, data: bytes) -> str:
    name = filename.lower()
    if kind == "photo":
        if data[:3] == b"\xff\xd8\xff" and name.endswith((".jpg", ".jpeg")):
            return "image/jpeg"
        if data[:8] == b"\x89PNG\r\n\x1a\n" and name.endswith(".png"):
            return "image/png"
        raise bad_request("invalid_file_type", "Cabinet photo must be a JPG/JPEG or PNG file (extension and file signature must match).")
    if kind == "drawing":
        if data[:5] == b"%PDF-" and name.endswith(".pdf"):
            return "application/pdf"
        raise bad_request("invalid_file_type", "GA drawing must be a PDF file.")
    if name.endswith((".xlsx", ".xlsm")) and data[:2] == b"PK":
        return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    if name.endswith(".xls") and data[:8] == b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1":
        return "application/vnd.ms-excel"
    if name.endswith(".csv") and b"\x00" not in data[:4096]:
        return "text/csv"
    raise bad_request("invalid_file_type", "Expected list must be an .xlsx, .xls or .csv file.")


def analyze_asset(kind: str, filename: str, data: bytes) -> dict:
    try:
        if kind == "photo":
            dec = decode_image(data)
            q = assess_quality(dec.bgr)
            return {"format": dec.format, "width": dec.bgr.shape[1], "height": dec.bgr.shape[0], "exif_orientation": dec.exif_orientation, "quality": q}
        if kind == "drawing":
            return inspect_pdf(data)
        return analyze_workbook(data, filename)
    except ImageDecodeError as exc:
        raise bad_request("unreadable_image", str(exc)) from exc
    except PdfError as exc:
        raise bad_request("unreadable_pdf", str(exc)) from exc
    except SheetError as exc:
        raise bad_request("unreadable_spreadsheet", str(exc)) from exc


def safe_display_name(filename: str) -> str:
    base = re.split(r"[\\/]", filename or "upload")[-1]
    base = re.sub(r"[^\w.\- ()]+", "_", base).strip() or "upload"
    return base[:200]


def store_asset(db: Session, v: InspectionVersion, kind: str, filename: str, data: bytes) -> InputAsset:
    s = get_settings()
    if kind not in KINDS:
        raise bad_request("invalid_kind", f"kind must be one of {sorted(KINDS)}")
    limit = {"photo": s.max_image_mb, "drawing": s.max_pdf_mb, "expected_list": s.max_sheet_mb}[kind] * 1024 * 1024
    if len(data) == 0:
        raise bad_request("empty_file", "The uploaded file is empty.")
    if len(data) > limit:
        raise ApiError(413, "file_too_large", f"File exceeds the {limit // (1024 * 1024)} MB limit for {kind}.")
    filename = safe_display_name(filename)
    ctype = _sniff(kind, filename, data)
    analysis = analyze_asset(kind, filename, data)
    st = get_storage()
    ext = {"image/jpeg": "jpg", "image/png": "png", "application/pdf": "pdf", "text/csv": "csv", "application/vnd.ms-excel": "xls"}.get(ctype, "xlsx")
    key = st.make_key("inspections", v.inspection_id, v.id, "inputs", ext=ext)
    sha, size = st.put_bytes(key, data)
    for old in [a for a in v.assets if a.kind == kind]:
        db.delete(old)
    asset = InputAsset(inspection_id=v.inspection_id, version_id=v.id, kind=kind, original_filename=filename, storage_key=key, content_type=ctype,
                       size_bytes=size, sha256=sha, analysis=analysis)
    db.add(asset)
    db.flush()
    db.refresh(v)
    audit(db, "asset_uploaded", "asset", asset.id, v.inspection_id, {"kind": kind, "filename": filename, "sha256": sha, "size": size, "version_no": v.version_no}, actor=reviewer())
    return asset


def create_reinspection(db: Session, insp: Inspection, label: str | None, reuse_photo: bool, config_overrides: dict | None = None) -> InspectionVersion:
    versions = sorted(insp.versions, key=lambda v: v.version_no)
    if any(v.status in ("queued", "running") for v in versions):
        raise conflict("run_in_progress", "A run is in progress for this inspection; wait for it to finish.")
    parent = next((v for v in reversed(versions) if v.status == "completed"), None)
    if parent is None:
        raise conflict("no_completed_version", "Reinspection requires a completed earlier version.")
    cfg = merged_config(parent.config)
    cfg["manual_anchors"] = None
    # carry inspector zone corrections forward
    drw = db.scalar(select(Drawing).where(Drawing.version_id == parent.id))
    if drw and any(z.source == "manual" for z in drw.zones):
        cfg["manual_zones"] = [{"code": z.code, "name": z.name, "bbox": [z.x0, z.y0, z.x1, z.y1]} for z in drw.zones]
    if config_overrides:
        cfg.update(config_overrides)
    nv = InspectionVersion(inspection_id=insp.id, version_no=versions[-1].version_no + 1, label=label or "Reinspection", parent_version_id=parent.id, status="draft", config=cfg)
    db.add(nv)
    db.flush()
    for a in parent.assets:
        if a.kind == "photo" and not reuse_photo:
            continue
        db.add(InputAsset(inspection_id=insp.id, version_id=nv.id, kind=a.kind, original_filename=a.original_filename, storage_key=a.storage_key,
                          content_type=a.content_type, size_bytes=a.size_bytes, sha256=a.sha256, analysis=a.analysis, inherited_from_asset_id=a.id))
    db.flush()
    db.refresh(nv)
    audit(db, "reinspection_created", "version", nv.id, insp.id, {"version_no": nv.version_no, "parent_version_no": parent.version_no, "reuse_photo": reuse_photo}, actor=reviewer())
    return nv
