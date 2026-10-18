"""End-to-end run of the real pipeline (YOLOv8 + OCR) on the bundled synthetic fixture.

Slow (≈1–2 min on CPU). Skipped when model weights are missing. Asserts the verdicts for the
deliberate discrepancies documented in data/demo/fixtures.json, then exercises review,
reinspection, comparison and report generation.
"""
import time

import pytest

from app.core.config import get_settings


def _wait(client, job_id, timeout=900):
    t0 = time.time()
    while time.time() - t0 < timeout:
        j = client.get(f"/api/v1/jobs/{job_id}").json()
        if j["status"] in ("completed", "failed", "cancelled"):
            return j
        time.sleep(2)
    raise AssertionError("job timed out")


@pytest.mark.slow
def test_sample_inspection_end_to_end(client, demo_dir):
    s = get_settings()
    if not s.detector_weights.is_file() or not s.easyocr_model_dir.is_dir():
        pytest.skip("model weights not installed (see models/README.md)")
    r = client.post("/api/v1/demo/sample-inspection", json={"variant": "v1", "run": True})
    assert r.status_code == 201
    insp = r.json()["inspection"]
    j = _wait(client, r.json()["job"]["id"])
    assert j["status"] == "completed", j
    assert all(st["status"] in ("completed", "needs_review") for st in j["stages"])
    vid = insp["versions"][0]["id"]
    items = client.get(f"/api/v1/versions/{vid}/findings").json()["items"]
    by = {f["finding_key"]: f for f in items}
    assert by["drawing_alignment"]["verdict"] == "PASS"
    assert by["component_presence:CB44"]["verdict"] == "FAIL"
    assert by["device_label:PS12"]["verdict"] == "FAIL"
    assert by["device_label:K2"]["verdict"] == "UNCERTAIN"
    assert by["ferrule:X12:4"]["verdict"] == "FAIL"
    assert by["ferrule:X12:6"]["verdict"] == "UNCERTAIN"
    # human review is stored separately; machine verdict unchanged
    fid = by["ferrule:X12:6"]["id"]
    rv = client.post(f"/api/v1/findings/{fid}/reviews", json={"action": "resolve_fail", "notes": "misprinted ferrule"})
    assert rv.status_code == 201
    fd = client.get(f"/api/v1/findings/{fid}").json()
    assert fd["verdict"] == "UNCERTAIN" and fd["effective_verdict"] == "FAIL"
    assert client.post(f"/api/v1/findings/{fid}/reviews", json={"action": "waive"}).status_code == 400  # reason required
    # evidence + reports
    assert any(e["kind"] == "finding_crop" for e in fd["evidence"])
    for fmt in ("pdf", "json", "csv", "xlsx"):
        rep = client.post(f"/api/v1/versions/{vid}/reports", json={"format": fmt})
        assert rep.status_code == 201, rep.text
        dl = client.get(rep.json()["download_url"])
        assert dl.status_code == 200 and len(dl.content) > 100
    # reinspection with corrected photo keeps v1 intact
    rr = client.post(f"/api/v1/demo/sample-inspection/{insp['id']}/reinspect")
    assert rr.status_code == 201
    j2 = _wait(client, rr.json()["job"]["id"])
    assert j2["status"] == "completed"
    cmp_ = client.get(f"/api/v1/inspections/{insp['id']}/compare").json()
    counts = cmp_["summary"]["counts"]
    assert counts.get("resolved", 0) >= 2
    v1_after = client.get(f"/api/v1/versions/{vid}/findings").json()["items"]
    assert {f["id"]: f["verdict"] for f in v1_after} == {f["id"]: f["verdict"] for f in items}
