# Handoff — continuing EAGLE EYE development

Give this file (and the repo URL + branch) to the next developer or AI assistant.

* Repo: `https://github.com/trivediyash154-source/eagleeye` · branch **`claude/nice-hopper-mf9z8s`**
* Original brief: the “MASTER BUILD PROMPT — PROJECT EAGLE EYE” (keep it alongside this file) and the
  team deck *EAGLE_EYE_CODE_APEX_ENHANCED_v3.pptx* (algorithms: zone graph, SIFT/ORB+RANSAC,
  Levenshtein rules, re-check loop).
* Current state: [docs/STATUS.md](docs/STATUS.md). Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Get it running (≈10 min + downloads)

```bash
git clone -b claude/nice-hopper-mf9z8s https://github.com/trivediyash154-source/eagleeye.git && cd eagleeye
./scripts/run_local.sh            # → http://localhost:8000
cd backend && pytest -m "not slow" && pytest -m slow     # 33 + 1 tests
cd ../frontend && flutter analyze && flutter test
```
Needs Python 3.11, Flutter 3.47+ (Dart 3.13), network access to PyPI, pub.dev and GitHub releases
(for `scripts/setup_models.sh`). `models/cache/` (YOLOv8n + EasyOCR weights) is git-ignored.

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
4. **Browser E2E automation**: Playwright script that clicks through the wizard (upload via file chooser),
   live job, workspace review, reinspection and report download (Flutter renders to canvas — enable
   semantics or use coordinates).
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
| 3D landing scene | `frontend/web/three/eagle_scene.js` + `features/landing/cabinet_scene_web.dart` |
| Design tokens | `frontend/lib/core/theme/tokens.dart` |

## Environment notes from the original build

* Built in a sandbox where `huggingface.co`, PaddleOCR model hosts, `download.pytorch.org`,
  `ultralytics.com`, `www.gstatic.com` and jsDelivr were blocked — hence EasyOCR, vendored three.js
  and fonts, `--no-web-resources-cdn`, and `scripts/setup_models.sh` downloading from GitHub releases.
* OpenCV 5 returns `HoughLinesP` as `(N,4)`; Ultralytics patches `PIL.Image.open` (HEIF) — both handled.
* SQLite does not enforce `VARCHAR` lengths; always run the suite on PostgreSQL before releasing.
