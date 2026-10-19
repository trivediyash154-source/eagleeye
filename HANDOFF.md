# Handoff — continuing EAGLE EYE development

Give this file (and the repo URL + branch) to the next developer or AI assistant.

* Repo: `https://github.com/trivediyash154-source/eagleeye` · branch **`claude/nice-hopper-mf9z8s`**
* Original brief: the “MASTER BUILD PROMPT — PROJECT EAGLE EYE” (keep it alongside this file) and the
  team deck *EAGLE_EYE_CODE_APEX_ENHANCED_v3.pptx* (algorithms: zone graph, SIFT/ORB+RANSAC,
  Levenshtein rules, re-check loop).
* Current state: [docs/STATUS.md](docs/STATUS.md). Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Get it running (≈10 min + downloads)

```bash
git clone https://github.com/trivediyash154-source/eagleeye.git && cd eagleeye
./scripts/run_local.sh            # Windows: powershell -ExecutionPolicy Bypass -File scripts\run_local.ps1
# → http://localhost:8000 opens the console directly (product overview page: /welcome)
cd backend && pip install -r requirements-dev.txt && pytest          # 33 fast + 1 real-model e2e test
python ../scripts/browser_smoke.py --base http://localhost:8000      # UI walkthrough (needs: python -m playwright install chromium)
```
Needs Python 3.11–3.13 and network access to PyPI and GitHub releases (model weights). **Flutter is
only needed to change the console**: the release build is committed in `frontend/prebuilt/web`; after
editing Dart code run `./scripts/build_web.sh` (Flutter 3.47+, Dart 3.13) and commit the refreshed
bundle. `models/cache/` (YOLOv8n + EasyOCR weights) is git-ignored and downloaded by the launchers.
The repository must be public, or the other person must be added as a collaborator, for `git clone` to work.

## Ground rules the project follows (keep them)

1. Never fabricate detections, OCR readings, metrics or history; failed inference must fail visibly.
2. Machine findings are immutable; human reviews are separate rows; versions are never overwritten.
3. FAIL needs reliable contrary evidence (registered position, supported class, readable & corroborated text); everything else is UNCERTAIN with a reason code.
4. Demo data is synthetic and must stay labelled (`is_demo`, DEMO tags, PDF watermark).
5. Keep confidence sources separate; no combined score without calibration data.
6. Any change to verification rules → add a unit test in `backend/tests/test_matching.py` / `test_drawing_and_verify.py` and re-run the slow e2e test.

## Suggested next steps (priority order)

1. **Real data**: collect and annotate real cabinet photos (YOLO format, same 7 classes); train
   `models/eagleeye-real-v1.pt`; add a held-out real validation set and report measured metrics with sample size.
2. **Create a `main` branch and open a PR** from `claude/nice-hopper-mf9z8s` (the repo had no base branch).
3. **Verify Docker** (`docker compose up --build`) and fix whatever the first real build reveals.
4. **Browser E2E in CI**: `scripts/browser_smoke.py` already clicks through every route, the sample run,
   review, PDF export, reinspection/compare and the upload wizard; wire it into a CI job.
5. **PaddleOCR**: install `paddlepaddle paddleocr` where its model hosts are reachable; compare with EasyOCR on ferrules.
6. **Performance**: OCR dominates (25–140 s on CPU). Options: skip full-image OCR when the detector
   supplies label/marker boxes, lower `EAGLEEYE_OCR_FULL_IMAGE_CANVAS`, GPU.
7. **Auth** (OIDC/JWT) + per-user review attribution; TLS via reverse proxy.
8. Raster/scanned GA drawings: add a scanned fixture and tests; zone editor click-to-draw.
9. Wire-colour check: validate under real lighting before enabling by default.

## Where things live

| Concern | File(s) |
|---|---|
| Pipeline stages & persistence | `backend/app/inspection/pipeline.py` |
| Verdict rules | `backend/app/inspection/verify.py`, `matching.py`, `ocr/normalize.py` |
| Registration | `backend/app/cv/registration.py` |
| Drawing parsing | `backend/app/drawing/pdf_parser.py` |
| Detector / OCR | `backend/app/cv/detector.py`, `backend/app/ocr/engines.py` |
| API | `backend/app/api/routes_*.py`, schemas `backend/app/schemas/api.py` |
| Reports | `backend/app/reporting/` |
| Synthetic renderer / training | `backend/app/demo/synth_cabinet.py`, `backend/scripts/*` |
| Flutter API client & models | `frontend/lib/core/api/` |
| Screens | `frontend/lib/features/<screen>/` (router: `frontend/lib/app/router.dart`) |
| 3D product overview (`/welcome`) | `frontend/web/three/eagle_scene.js` + `features/landing/cabinet_scene_web.dart` |
| Routing (`/` → `/console`) | `frontend/lib/app/router.dart`; API base URL resolution: `frontend/lib/core/config/app_config.dart` |
| One-command launchers | `scripts/run_local.sh`, `scripts/run_local.ps1`, `scripts/setup_models.sh`, `scripts/build_web.sh` |
| Design tokens | `frontend/lib/core/theme/tokens.dart` |

## Environment notes from the original build

* Built in a sandbox where `huggingface.co`, PaddleOCR model hosts, `download.pytorch.org`,
  `ultralytics.com`, `www.gstatic.com` and jsDelivr were blocked — hence EasyOCR, vendored three.js
  and fonts, `--no-web-resources-cdn`, and `scripts/setup_models.sh` downloading from GitHub releases.
* OpenCV 5 returns `HoughLinesP` as `(N,4)`; Ultralytics patches `PIL.Image.open` (HEIF) — both handled.
* SQLite does not enforce `VARCHAR` lengths; always run the suite on PostgreSQL before releasing.
