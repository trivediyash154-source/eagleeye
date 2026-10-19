# Four-minute presenter script

Preparation (before judges arrive): `./scripts/run_local.sh` (Windows: `scripts\run_local.ps1`), open
http://localhost:8000 (it opens the console; the 3D product overview is at http://localhost:8000/welcome), run the sample
once (Overview → **Run sample inspection**) so models are warm, and open History → *Reinspect with corrected
fixture photo (v2)* once so a comparison exists. Keep a second tab on the Workspace of the sample.

| Time | Screen | Say / do |
|---|---|---|
| 0:00–0:25 | Product overview (`/welcome`) | “EAGLE EYE checks a cabinet against its engineering specification — not just for objects.” Let the scan pass; point at the GA plane aligning and the PS21≠PS12 annotation. Note the live status panel: real backend, real models. |
| 0:25–0:55 | Overview ↓ Problem & Drawing-aware (then **Launch Inspection Console**) | Drawing vs photo; one-character identifiers decide terminals (X12-4B vs X12-8B). |
| 0:55–1:35 | New Inspection | Show the wizard: case info, photo quality diagnostics, PDF page/vector analysis, sheet + column mapping, checks (wire colour labelled experimental), readiness. Use “Use bundled demo fixtures” and **Run Inspection**. |
| 1:35–2:20 | Live Inspection | Real stage states and timings: drawing parsed (5 zones, 13/13 located), YOLOv8 tiles, OCR, registration by text anchors (15 inliers, ~0.2 px). Nothing is simulated. |
| 2:20–3:10 | Workspace | Filter FAIL: CB44 missing (crop shows empty rail), PS12 label PS21, X12:4 ferrule X12-8B. Open X12:6: X12-68 vs X12-6B → UNCERTAIN because 8/B are OCR-confusable — “the system asks a human instead of raising a false alarm”. Show confidence sources kept separate. |
| 3:10–3:40 | Review → History | Resolve X12:6 as FAIL with a note (machine verdict preserved). History: v1→v2 comparison — resolved items, still-uncertain items, v1 untouched. |
| 3:40–4:00 | Reports | Generate the PDF; scroll to the evidence pages. Close: “Bring your engineering specifications. Leave with evidence.” |

Honesty notes to say out loud if asked: demo inputs are synthetic; the detector was trained only on
synthetic renders; accuracy on real cabinets has not been measured.
