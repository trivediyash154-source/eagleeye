# EAGLE EYE — Intelligent Industrial Cabinet Inspection

**Team OpHackers** · Vraj Shah · Vedaant Uttarkar · Yash Trivedi · Veer Jain · *Track 3 PS 1*

> *“Every Component. Every Connection. Verified.”*
> EAGLE EYE turns a cabinet photograph, its General Arrangement (GA) drawing and an expected
> wire/label list into an evidence-backed inspection report of **PASS / FAIL / UNCERTAIN** findings.

It compares the real cabinet against its engineering specification — it does not merely detect
objects. Every verdict carries traceable photographic evidence, every uncertain item goes to a human
reviewer, and every re-inspection is stored as a new immutable version.

| | |
|---|---|
| **Frontend** | Flutter Web (Material 3, custom design system), Riverpod 3, go_router, fl_chart; Three.js landing scene |
| **Backend** | FastAPI · SQLAlchemy 2 · Alembic · SQLite (default) / PostgreSQL |
| **Vision** | OpenCV 5 · Ultralytics YOLOv8 (tiled inference) · EasyOCR (PaddleOCR adapter included) · PyMuPDF |
| **Reports** | ReportLab PDF · JSON · CSV · XLSX |

---

## Quick start (one command)

You need `git` and ~6 GB of free disk for PyTorch. Python 3.11–3.13 is used if installed; if not
(e.g. macOS ships 3.9), `run_local.sh` installs a private Python 3.11 with [uv](https://docs.astral.sh/uv)
inside the repo folder (`.tools/`), nothing system-wide. **No Flutter SDK is needed**: the built web
console is committed in `frontend/prebuilt/web` and served by the backend.

**Linux / macOS (Apple Silicon, macOS 14+)**

```bash
git clone https://github.com/trivediyash154-source/eagleeye.git
cd eagleeye
./scripts/run_local.sh            # first run: venv + dependencies + model weights (~5–10 min)
```

**Windows 10/11 (PowerShell)** — install Python 3.11 from python.org first (tick “Add python.exe to PATH”)

```powershell
git clone https://github.com/trivediyash154-source/eagleeye.git
cd eagleeye
powershell -ExecutionPolicy Bypass -File scripts\run_local.ps1
```

Open **<http://localhost:8000>**. The app opens directly in the inspection console (no sign-in);
click **Run sample inspection** on the Overview. The bundled synthetic fixture goes through the
*live* pipeline (≈1–3 min on a laptop CPU), the live view follows each stage, and the workspace
opens when it finishes. The product overview page with the 3D scene is at `/welcome`.

Later runs start in seconds (dependencies are reinstalled only when `requirements.txt` changes).
Use another port with `PORT=8080 ./scripts/run_local.sh` or `scripts\run_local.ps1 -Port 8080`.

| Platform | Status |
|---|---|
| Linux x86_64, Python 3.11 | Verified: fresh clone → `run_local.sh` → full test suite and browser walkthrough |
| Windows x64, macOS 14+ arm64, Linux arm64, Python 3.12/3.13 | Pinned dependencies resolve (checked with `uv pip compile`); not run on that hardware |
| Intel Mac, Python ≤ 3.10 | Not installable natively (no PyTorch 2.14 / OpenCV 5 wheels; SQLAlchemy 2.1 needs 3.11) — use Docker |

## Manual setup

```bash
# 1. backend dependencies (Python 3.11–3.13)
python3.11 -m venv .venv && . .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r backend/requirements.txt

# 2. third-party model weights (YOLOv8n COCO + EasyOCR) — not stored in git
./scripts/setup_models.sh                                  # Windows: run_local.ps1 does this

# 3. configuration (optional; defaults work for local use)
cp .env.example .env

# 4. run (migrations are applied automatically at startup; disable with EAGLEEYE_AUTO_MIGRATE=false)
cd backend && uvicorn app.main:app --host 127.0.0.1 --port 8000
```

* Console: <http://localhost:8000> · API docs (OpenAPI): <http://localhost:8000/api/v1/docs>
* The backend serves `frontend/build/web` if you built it yourself, otherwise `frontend/prebuilt/web`.
* Regenerate the demo fixtures / landing images (both committed):
  `cd backend && python scripts/generate_demo_fixtures.py && python scripts/build_landing_assets.py`
* Apply migrations manually: `cd backend && alembic upgrade head`.

### Changing the web console (Flutter 3.47+, Dart 3.13+)

```bash
cd frontend && flutter run -d chrome --web-port 8080    # hot reload; talks to the API on :8000
./scripts/build_web.sh                                  # release build → refreshes frontend/prebuilt/web
```
When the page is served by the backend (any port) the console calls the API on the same origin; a
Flutter dev server falls back to `http://<host>:8000`. Override with `--dart-define=API_BASE_URL=…`
or in **Settings**. Commit `frontend/prebuilt/web` after `build_web.sh` so others get the change.

### PostgreSQL

```bash
export EAGLEEYE_DATABASE_URL=postgresql+psycopg://eagleeye:PASSWORD@localhost:5432/eagleeye
cd backend && alembic upgrade head && uvicorn app.main:app --port 8000
```
Verified: the full test suite (including the real-model end-to-end test) passes on PostgreSQL 16.

### Docker Compose

```bash
cp .env.example .env     # set POSTGRES_PASSWORD
docker compose up --build   # http://localhost:8000
```
> ⚠️ The `Dockerfile`/`docker-compose.yml` were written but **could not be built** in the authoring
> environment (no Docker daemon). Treat them as a starting point and verify on your machine.

## Tests

```bash
cd backend
pip install -r requirements-dev.txt
pytest -m "not slow"     # 33 fast tests (rules, parsing, registration, transforms, storage, API)
pytest -m slow           # real YOLOv8 + OCR end-to-end: sample → review → reports → reinspect → compare
cd ../frontend && flutter analyze && flutter test
```

## What happens in an inspection

`validation → preprocessing → drawing → detection → OCR → registration → verification → evidence → report`

1. **Ingest** – extension + file-signature + size validation, EXIF orientation, quality diagnostics
   (Laplacian sharpness, brightness, contrast, glare), CLAHE; originals are never modified.
2. **Drawing** – PyMuPDF words/rectangles (OCR at 300 DPI for raster sheets), zone frames (`Z1…`),
   label plates and component bodies located for every expected tag and ferrule.
3. **Detection** – YOLOv8 full-image + overlapping tiles, border-box suppression, class-wise NMS;
   boxes mapped back to original pixels. All detections ≥ 0.05 stored; threshold 0.35 for “positive”.
4. **OCR** – full image + crops of detected labels/markers (3 preprocessing variants combined by
   consensus; a reading the variants do not corroborate is UNCERTAIN); raw text kept, every
   normalisation step recorded; I/O excluded (IEC 81346).
5. **Registration** – SIFT/ORB + RANSAC, and *text anchors* (identifiers unique in both drawing and
   photo) + RANSAC; accepted only if inliers, ratio, coverage, orientation, convexity, scale,
   perspective and reprojection checks all pass. Manual 4-point alignment as fallback.
6. **Verification** – deterministic rules (see `backend/app/inspection/verify.py`, `matching.py`).
7. **Evidence & report** – crops, annotated overlays, registration overlay, PDF report.

### Verdict policy (default: confusion-aware)

| Situation | Verdict |
|---|---|
| exact normalised match, OCR conf ≥ 0.45, reliable position | **PASS** |
| differs only by OCR-confusable chars (8/B, 0/O, 1/I, 5/S, 2/Z, 6/G) | **UNCERTAIN** |
| no readable text, partial read, low confidence, ambiguous association | **UNCERTAIN** |
| reliable reading (conf ≥ 0.55) differing by a non-confusable edit | **FAIL** |
| component not detected at a *registered* position, class supported, region in frame | **FAIL** |
| registration unavailable / class unsupported | **UNCERTAIN** (never FAIL) |

`distance_bands` (the original deck rule: d=0 PASS, d=1 UNCERTAIN, d≥2 FAIL) is selectable per
identifier type. Note: the deck’s example *X12-4B vs X12-8B* is Levenshtein **1**, not 2 — the
confusion-aware policy is what correctly reports it as a FAIL (4/8 are not confusable).

## Demonstration data — honest labelling

* `data/demo/` holds **synthetic** fixtures for cabinet *CAB-07* (procedurally rendered 4000×3000
  photo, vector GA drawing, expected list). `fixtures.json` lists the deliberate discrepancies.
* `models/eagleeye-synth-v1.pt` is YOLOv8n fine-tuned **only on synthetic renders**
  (`backend/scripts/build_synthetic_dataset.py`, `train_synthetic_detector.py`). Its synthetic-val
  mAP50 0.995 says nothing about real cabinets. If removed, the system falls back to COCO
  `yolov8n.pt`, which has no cabinet classes → presence/type checks report UNCERTAIN.
* Demo inspections are flagged `is_demo` everywhere (UI tag, PDF watermark, analytics filter).
  Results are always produced by the live pipeline — no precomputed results are served.

## Repository layout

```
backend/   FastAPI app (app/api, core, models, schemas, services, cv, ocr, drawing, inspection,
           storage, reporting, workers, demo), Alembic migrations, scripts/, tests/
frontend/  Flutter web console (lib/app, lib/core, lib/features/*), web/three/eagle_scene.js
models/    custom detector weights + metrics (third-party weights downloaded to models/cache/)
data/demo/ synthetic fixtures
docs/      architecture, API, demo script, troubleshooting, status, openapi.json
scripts/   run_local.sh / run_local.ps1 (one-command start), setup_models.sh, build_web.sh
frontend/prebuilt/web   committed release build of the console (no Flutter needed to run)
```

## Documentation

* [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — components, data model, coordinate conventions
* [docs/API.md](docs/API.md) — endpoint reference (+ `docs/openapi.json`)
* [docs/DEMO_SCRIPT.md](docs/DEMO_SCRIPT.md) — four-minute presenter script
* [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — model/OCR/registration/browser issues
* [docs/STATUS.md](docs/STATUS.md) — verified features, incomplete capabilities, known limitations
* [docs/SECURITY.md](docs/SECURITY.md) — security, privacy and encryption boundaries
* [models/README.md](models/README.md) — weights and custom training
* [HANDOFF.md](HANDOFF.md) — context for continuing development

*EAGLE EYE supports inspection and human review. It does not certify a cabinet as compliant.*
