# API reference (v1)

Base path: `/api/v1`. Interactive docs: `http://localhost:8000/api/v1/docs`. Machine-readable spec:
[`openapi.json`](openapi.json) (regenerate: `cd backend && python -c "import json; from app.main import app; json.dump(app.openapi(), open('../docs/openapi.json','w'), indent=1)"`).

**Errors** always use `{"error": {"code", "message", "details"}}` with proper status codes
(400 validation/business rule, 404 not found, 409 conflict/immutable, 413 too large, 422 schema, 503 model unavailable).

**Coordinates**: image boxes are `[x0, y0, x1, y1]` in *original-frame* pixels (after EXIF orientation);
drawing boxes are PDF points, origin top-left, y down. Registration `homography` maps drawing points → photo pixels.

## Typical flow

```text
POST /inspections                          → inspection + version 1 (draft)
POST /versions/{vid}/assets  kind=photo|drawing|expected_list (multipart)
PATCH /versions/{vid}/config               checks, drawing_page, sheets mapping, policies
GET  /versions/{vid}/readiness
POST /versions/{vid}/run                   → job (202)
GET  /jobs/{job_id}                        poll stages
GET  /versions/{vid}/findings              → findings + counts
GET  /findings/{fid}                       → detail incl. evidence, reviews, history
POST /findings/{fid}/reviews               confirm | resolve_pass | resolve_fail | false_positive | correct_observed | waive | mark_reviewed | note
POST /inspections/{id}/reinspect           → new draft version (inputs inherited, optional new photo)
GET  /inspections/{id}/compare             → resolved / persistent / new / still-uncertain …
POST /versions/{vid}/reports {format}      pdf | json | csv | xlsx  → GET /reports/{rid}/download
```

## Endpoints

| Method | Path | Summary |
|---|---|---|
| `GET` | `/api/v1/health` | Liveness probe |
| `GET` | `/api/v1/system/status` | Readiness of every subsystem (real checks) |
| `GET` | `/api/v1/system/diagnostics` | Detector, OCR and pipeline diagnostics |
| `POST` | `/api/v1/system/models/load` | Load detector and OCR models now |
| `GET` | `/api/v1/system/logs` | Recent structured operational events (redacted) |
| `GET` | `/api/v1/system/checks` | Inspection checks and their availability with the loaded models |
| `POST` | `/api/v1/system/diagnostics/detector-test` | Run the loaded detector on a test image |
| `POST` | `/api/v1/system/diagnostics/ocr-test` | Run the OCR engine on a test image |
| `POST` | `/api/v1/inspections` | Create an inspection case (version 1 in draft) |
| `GET` | `/api/v1/inspections` | List inspections with search, filters, sorting and pagination |
| `GET` | `/api/v1/inspections/{inspection_id}` | Get Inspection |
| `PATCH` | `/api/v1/inspections/{inspection_id}` | Update Inspection |
| `GET` | `/api/v1/inspections/{inspection_id}/timeline` | Audit trail for the inspection |
| `POST` | `/api/v1/inspections/{inspection_id}/reinspect` | Create a new version; earlier versions stay intact |
| `GET` | `/api/v1/inspections/{inspection_id}/compare` | Compare two versions by stable finding keys |
| `GET` | `/api/v1/versions/{version_id}` | Get Version |
| `PATCH` | `/api/v1/versions/{version_id}/config` | Update checks, page, sheet mapping and thresholds of a draft version |
| `POST` | `/api/v1/versions/{version_id}/assets` | Upload (or replace) the photo, GA drawing or expected list |
| `DELETE` | `/api/v1/versions/{version_id}/assets/{asset_id}` | Delete Asset |
| `GET` | `/api/v1/versions/{version_id}/readiness` | Pre-run validation of inputs, models and storage |
| `POST` | `/api/v1/versions/{version_id}/run` | Start the inspection pipeline for a version |
| `GET` | `/api/v1/versions/{version_id}/media` | Key images for a version (original, annotated, overlays, drawing render) |
| `GET` | `/api/v1/versions/{version_id}/detections` | Version Detections |
| `GET` | `/api/v1/versions/{version_id}/ocr` | Version Ocr |
| `GET` | `/api/v1/versions/{version_id}/expected` | Version Expected |
| `GET` | `/api/v1/versions/{version_id}/drawing` | Parsed drawing, zones, located identifiers and their projection onto the photo |
| `PUT` | `/api/v1/versions/{version_id}/zones` | Correct zone definitions (persisted on the drawing record; applied by the next run) |
| `POST` | `/api/v1/versions/{version_id}/alignment` | Manual anchor alignment; for a completed version this creates a new version |
| `GET` | `/api/v1/assets/{asset_id}/pdf/pages/{page}/preview` | Render a PDF page preview (PNG) |
| `POST` | `/api/v1/assets/{asset_id}/spreadsheet/preview` | Parse the expected list with a sheet/column mapping and return records + warnings |
| `GET` | `/api/v1/jobs` | Active and recent processing jobs |
| `GET` | `/api/v1/jobs/{job_id}` | Get Job |
| `POST` | `/api/v1/jobs/{job_id}/cancel` | Request cancellation (honoured between stages) |
| `GET` | `/api/v1/versions/{version_id}/findings` | Findings of a version with filters |
| `GET` | `/api/v1/findings/{finding_id}` | Get Finding |
| `POST` | `/api/v1/findings/{finding_id}/reviews` | Record a human review decision (machine finding stays unchanged) |
| `GET` | `/api/v1/evidence` | Browse evidence assets |
| `GET` | `/api/v1/evidence/{evidence_id}/file` | Download/stream an evidence image (thumb=1 for a thumbnail) |
| `GET` | `/api/v1/assets/{asset_id}/file` | Download an uploaded input file |
| `POST` | `/api/v1/versions/{version_id}/reports` | Generate a report/export: pdf | json | csv | xlsx |
| `GET` | `/api/v1/reports` | List generated reports |
| `GET` | `/api/v1/reports/{report_id}/download` | Download Report |
| `GET` | `/api/v1/analytics/overview` | KPIs and distributions computed from persisted records |
| `GET` | `/api/v1/analytics/activity` | Recent activity feed |
| `GET` | `/api/v1/review-queue` | Findings needing human review, with reasons |
| `GET` | `/api/v1/demo/fixtures` | Bundled synthetic demonstration fixtures |
| `GET` | `/api/v1/demo/fixtures/{name}` | Download a fixture file |
| `POST` | `/api/v1/demo/sample-inspection` | Create a demo inspection from fixtures and run the live pipeline |
| `POST` | `/api/v1/demo/sample-inspection/{inspection_id}/reinspect` | Reinspect a demo inspection with the corrected (v2) fixture photo |
