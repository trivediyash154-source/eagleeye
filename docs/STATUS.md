# Status — what is verified, what is not

Snapshot of the build on branch `claude/nice-hopper-mf9z8s`. "Verified" means exercised in the
authoring environment (Linux, 4 CPU cores, no GPU, Python 3.11, Flutter 3.47.7, Chromium via Playwright).

## Verified

| Area | Evidence |
|---|---|
| Backend tests | 33 fast tests + 1 real-model end-to-end test pass on **SQLite** and on **PostgreSQL 16** (Alembic migration applied). |
| Real YOLOv8 inference | `eagleeye-synth-v1.pt` on CPU, 20 tiles on a 4000×3000 image in ≈1–6 s; COCO fallback path implemented. |
| Real OCR | EasyOCR 1.7.2 (full image + crop variants with consensus). PaddleOCR adapter present but **not testable** here (model hosts blocked). |
| Full upload → report journey (API) | `tests/test_pipeline_e2e.py`: sample inspection → verdicts match fixture ground truth → review stored separately → PDF/JSON/CSV/XLSX downloaded → reinspection with corrected photo → comparison (≥2 resolved, **0 false new discrepancies**) → v1 unchanged. |
| Registration | Text-anchor homography on the fixture: 15 inliers, 0.22–0.23 px median reprojection error; validation checks unit-tested (mirror/too-few-anchors rejected); manual anchors unit-tested. |
| Fixture ground truth (v1) | CB44 missing → FAIL · PS12 “PS21” → FAIL · X12:4 “X12-8B” → FAIL · X12:6 “X12-68” → UNCERTAIN (confusable) · K2 occluded → UNCERTAIN · alignment PASS. |
| Web console in a browser | Production build served by FastAPI at `http://localhost:8000`; screenshots verified for Landing (live Three.js scene), Overview, Live Inspection, Workspace, OCR, New Inspection wizard (fixture shortcut uploads real files). |
| Flutter | `flutter analyze` clean; 8 widget/unit tests pass. |
| Maintenance | `python -m app.maintenance verify` (SHA-256 integrity of 115 files: OK), `purge --dry-run`. |

## Implemented but not fully exercised

* Drawing Intelligence zone editor and manual-alignment tool UI (backend endpoints tested via unit tests; UI compiled and rendered, click-through not automated).
* Detection / Evidence / Review queue / History / Reports / Diagnostics / Health / Settings screens: compile cleanly and load real data; not every interaction was clicked through in a browser.
* Raster (scanned) GA drawings: OCR-at-300-DPI path and contour rectangles implemented; no scanned fixture tested.
* Wire-colour check (experimental, off by default): implemented; not validated.
* Docker / docker-compose: written, **never built** (no Docker daemon available).
* Drag-and-drop upload on web: implemented; verified only via the file-picker/fixture path.

## Known limitations (by design or out of scope)

* The detector was trained **only on synthetic renders**; it will not generalise to real cabinet photos. Real annotated data is required (see `models/README.md`).
* No validated real-world dataset → **no accuracy metric is reported** anywhere.
* OCR on CPU is slow (25–140 s per 12 MP photo depending on load); dominant cost of a run.
* Planar homography ignores component depth (parallax) for oblique photos.
* No authentication/authorisation (local demo identity only); no TLS in the dev server.
* No combined/calibrated confidence score (sources are reported separately).
* Single in-process worker (no Redis/Celery); jobs running during a server restart are marked failed and can be re-run.
* The repo has no `main`/default branch yet (it was empty), so no pull request could be opened.
