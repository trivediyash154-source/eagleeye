"""Demonstration mode.

Sample inspections are created from the bundled SYNTHETIC fixtures in data/demo and processed by
the real pipeline (live YOLOv8 + OCR inference). They are flagged ``is_demo`` everywhere so they
are never mixed with real inspections. No precomputed results are served.
"""
from __future__ import annotations

import json

from fastapi import APIRouter, Depends
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..core.config import get_settings
from ..core.db import get_db
from ..core.errors import ApiError, conflict, not_found
from ..inspection.pipeline import create_job
from ..schemas.api import SampleInspectionIn
from ..services import inspections as svc
from ..services.serialize import inspection_out, job_out, version_out
from ..workers.jobs import submit

router = APIRouter(tags=["demo"])


def _manifest() -> dict:
    p = get_settings().demo_dir / "fixtures.json"
    if not p.is_file():
        raise ApiError(404, "fixtures_missing", "Demo fixtures are not installed. Run: python backend/scripts/generate_demo_fixtures.py")
    return json.loads(p.read_text(encoding="utf-8"))


@router.get("/demo/fixtures", summary="Bundled synthetic demonstration fixtures")
def fixtures():
    try:
        m = _manifest()
    except ApiError as exc:
        return {"installed": False, "message": exc.message, "files": []}
    d = get_settings().demo_dir
    files = []
    for role, name in m["files"].items():
        p = d / name
        files.append({"role": role, "name": name, "size_bytes": p.stat().st_size if p.is_file() else None, "present": p.is_file(), "url": f"/api/v1/demo/fixtures/{name}"})
    return {"installed": True, "notice": m["notice"], "files": files, "ground_truth_discrepancies_v1": m["ground_truth_discrepancies_v1"],
            "fixed_in_v2": m["fixed_in_v2"], "still_present_in_v2": m["still_present_in_v2"]}


@router.get("/demo/fixtures/{name}", summary="Download a fixture file")
def fixture_file(name: str):
    m = _manifest()
    if name not in m["files"].values():
        raise not_found("fixture", name)
    return FileResponse(get_settings().demo_dir / name, filename=name)


@router.post("/demo/sample-inspection", status_code=201, summary="Create a demo inspection from fixtures and run the live pipeline")
def sample_inspection(body: SampleInspectionIn, db: Session = Depends(get_db)):
    m = _manifest()
    d = get_settings().demo_dir
    insp = svc.create_inspection(db, {
        "title": "CAB-07 sample inspection (synthetic fixture)", "cabinet_id": "CAB-07", "site": "Demonstration bench — synthetic data",
        "reference": "DEMO-CAB-07", "inspector": "Demo walkthrough", "project_ref": "EAGLE EYE demo",
        "notes": "Inputs are bundled SYNTHETIC fixtures (computer-generated photo, GA drawing and lists). Results are produced live by the pipeline.",
    }, is_demo=True)
    v = insp.versions[0] if insp.versions else None
    db.flush()
    db.refresh(insp)
    v = insp.versions[0]
    photo = m["files"]["photo_v2" if body.variant == "v2" else "photo_v1"]
    for kind, name in (("photo", photo), ("drawing", m["files"]["drawing"]), ("expected_list", m["files"]["expected_list"])):
        svc.store_asset(db, v, kind, name, (d / name).read_bytes())
    job = None
    if body.run:
        job = create_job(db, v)
    db.commit()
    if job:
        submit(job.id)
    db.refresh(insp)
    return {"inspection": inspection_out(db, insp, with_versions=True), "job": job_out(job) if job else None, "source": "live pipeline on bundled synthetic fixtures"}


@router.post("/demo/sample-inspection/{inspection_id}/reinspect", status_code=201, summary="Reinspect a demo inspection with the corrected (v2) fixture photo")
def sample_reinspect(inspection_id: str, db: Session = Depends(get_db)):
    m = _manifest()
    insp = svc.get_inspection(db, inspection_id)
    if not insp.is_demo:
        raise conflict("not_demo", "Only demonstration inspections can be reinspected with fixture photos.")
    nv = svc.create_reinspection(db, insp, "Reinspection after corrections (fixture photo v2)", reuse_photo=False)
    name = m["files"]["photo_v2"]
    svc.store_asset(db, nv, "photo", name, (get_settings().demo_dir / name).read_bytes())
    job = create_job(db, nv)
    db.commit()
    submit(job.id)
    db.refresh(nv)
    return {"version": version_out(db, nv), "job": job_out(job)}
