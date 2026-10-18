# Architecture

```
Flutter Web console (Riverpod, go_router, fl_chart, Three.js landing)
        │  HTTPS/JSON (Dio)                      same origin when served by the API
        ▼
FastAPI  /api/v1 ── routes_system / routes_inspections / routes_findings / routes_demo
        │                                   │
        │ services (inspections, analytics, │ workers.jobs  (ThreadPoolExecutor, persisted job/stage rows,
        │ diagnostics, serialize, common)   │               recovery of interrupted jobs at startup)
        ▼                                   ▼
SQLAlchemy 2 ── SQLite | PostgreSQL      inspection.pipeline.PipelineRunner (9 stages)
Alembic migrations                         ├─ cv.preprocess   EXIF, quality, CLAHE, tracked transforms
                                           ├─ drawing.pdf_parser  PyMuPDF words/rects, zones, tag location, raster OCR
storage.local  (generated keys, SHA-256,   ├─ cv.detector     YOLOv8, tiling, border suppression, NMS
 path-traversal protection)                ├─ ocr.engines     PaddleOCR | EasyOCR, crop variants + consensus
                                           ├─ cv.registration SIFT/ORB, text anchors, manual, validation checks
reporting  (ReportLab PDF, JSON/CSV/XLSX)  ├─ inspection.verify + matching  deterministic rules
                                           └─ evidence + report
```

## Data model (all tables have string IDs with prefixes, FK constraints, UTC timestamps)

`inspections` 1─* `inspection_versions` (immutable runs; `parent_version_id` for reinspections)
`inspection_versions` 1─* `input_assets` (metadata + sha256; bytes in storage; inherited assets reference the same key)
`inspection_versions` 1─1 `drawings` 1─* `drawing_zones`
`inspection_versions` 1─* `expected_components`, `expected_identifiers` (from the list, with drawing locations)
`inspection_versions` 1─* `detections`, `ocr_observations` (raw + normalised + steps + alternatives)
`inspection_versions` 1─* `findings` (immutable machine verdicts) 1─* `review_decisions` (human, separate rows)
`evidence_assets` (crops, overlays, renders; `error` when evidence could not be produced)
`processing_jobs` 1─* `processing_stages`; `reports`; `version_comparisons`; `model_configurations`; `audit_events`

*Effective verdict* = latest review decision that sets a verdict, else the machine verdict.

## Confidence handling

Detector confidence, OCR confidence, edit distance / similarity, registration metrics and the number of
agreeing OCR readings are stored **separately** on each finding. No combined score is computed
(`combined: null` with an explanatory note) because no calibration data exists.

## Frontend structure

`lib/app` (router, shell, brand) · `lib/core` (api client + typed models, config, providers, theme
tokens, widgets: Panel, VerdictBadge, OverlayImageViewer, InspectionScope …) · `lib/features/*` one
folder per screen. `web/three/eagle_scene.js` is the only JS; it is mounted through an
`HtmlElementView` (`features/landing/cabinet_scene_web.dart`) with a Flutter fallback painter when
WebGL is unavailable. Polling: system status 10 s, active jobs 4 s, live job 1.5 s (timers cancelled on dispose).
