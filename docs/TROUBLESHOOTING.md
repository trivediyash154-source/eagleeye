# Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Console shows “Backend not reachable” | API not running or wrong base URL. Start it with `./scripts/run_local.sh`; check **Settings → API base URL** (a page served by the backend uses its own origin on any port; a Flutter dev server falls back to `http://<host>:8000`). A URL saved in Settings overrides this — **Reset to default** clears it. |
| `Port 8000 is already in use` | Another EAGLE EYE (or other server) is running. Stop it, or `PORT=8001 ./scripts/run_local.sh` / `scripts\run_local.ps1 -Port 8001`. |
| `Python 3.11–3.13 not found` / pip cannot find `torch==…`, `sqlalchemy==2.1.5` or `opencv-python-headless==5.0.0.93` | Unsupported interpreter or platform: needs 64-bit Python 3.11–3.13 on Linux, Windows x64 or macOS 14+ Apple Silicon. Intel Macs and Python 3.10 cannot install natively — use Docker. Point the launcher at an interpreter with `PYTHON=/path/to/python3.11`. |
| Windows: “running scripts is disabled on this system” | Start the launcher with `powershell -ExecutionPolicy Bypass -File scripts\run_local.ps1` (affects only that process). |
| `No space left on device` during install | PyTorch needs ~5 GB in `.venv`. Free space, or point `EAGLEEYE_VENV` at another disk. |
| Old console after `git pull` | The browser cached the previous build; hard-reload (Ctrl+Shift+R). `index.html` is served with `Cache-Control: no-cache`. |
| YOLO status `unavailable` | No weights at `EAGLEEYE_DETECTOR_WEIGHTS` / fallback. Run `./scripts/setup_models.sh`; check `models/eagleeye-synth-v1.pt` exists (git LFS not used; plain file). |
| YOLO status `degraded (generic_coco)` | Custom weights missing → COCO fallback, which has no cabinet classes. Presence/type checks become UNCERTAIN by design. |
| OCR `unavailable` | EasyOCR weights missing in `models/cache/easyocr` (run setup script) or `EAGLEEYE_OCR_ALLOW_DOWNLOAD=false` with no files. PaddleOCR errors are listed per engine in Model Diagnostics. |
| Slow processing | CPU inference: full-image OCR dominates (25–140 s on a 4000×3000 photo). Use a GPU (`EAGLEEYE_DETECTOR_DEVICE=cuda:0`, `EAGLEEYE_OCR_GPU=true`) or lower `EAGLEEYE_OCR_FULL_IMAGE_CANVAS`. |
| Registration `insufficient/failed` | Too few identifiers shared by drawing text and photo OCR, or photo too oblique. Use **Drawing Intelligence → Manual alignment** (≥4 point pairs) which re-runs as a new version. |
| Many ferrules UNCERTAIN | Labels too small in the photo (< ~20 px text height). Photograph closer / higher resolution; confusable pairs (8/B, 0/O) are UNCERTAIN on purpose. |
| Spreadsheet “no records parsed” | Map columns in New Inspection step 4 (Component ID or Ferrule/Terminal must be mapped); header row is auto-detected but editable. |
| `/welcome` shows a static drawing instead of 3D | WebGL unavailable (headless/remote desktop/blocked GPU). The fallback is intentional. |
| `ModuleNotFoundError: pi_heif` in logs | Ultralytics tries HEIF for unknown files; harmless — non-JPEG/PNG uploads are rejected with 400. |
| PostgreSQL `value too long` | Report it: column lengths are enforced on PostgreSQL but not SQLite. Tests run on both. |
| Deep link 404 when serving the build elsewhere | Configure SPA fallback to `index.html` (the FastAPI server does this automatically). |
