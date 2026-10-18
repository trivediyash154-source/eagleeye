"""PDF inspection report (ReportLab).

The report supports inspection and human review. It is explicitly NOT a certificate of
compliance, and says so on the first page.
"""
from __future__ import annotations

import io
from datetime import datetime, timezone

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    Image as RLImage, KeepTogether, PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle,
)
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.util import iso
from ..cv.detector import get_detector
from ..models import EvidenceAsset, Finding, Inspection, InspectionVersion, ModelConfiguration, Report, VersionComparison
from ..services.common import audit, effective_verdict
from ..storage.local import get_storage

INK = colors.HexColor("#0B1220")
MUTED = colors.HexColor("#5B6577")
LINE = colors.HexColor("#D5DAE3")
CYAN = colors.HexColor("#0891B2")
VERDICT_COL = {"PASS": colors.HexColor("#059669"), "FAIL": colors.HexColor("#DC2626"), "UNCERTAIN": colors.HexColor("#D97706"), "WAIVED": colors.HexColor("#6B7280")}


def _styles():
    ss = getSampleStyleSheet()
    base = ParagraphStyle("base", parent=ss["Normal"], fontName="Helvetica", fontSize=8.6, leading=11.2, textColor=INK)
    return {
        "base": base,
        "small": ParagraphStyle("small", parent=base, fontSize=7.4, leading=9.4, textColor=MUTED),
        "cell": ParagraphStyle("cell", parent=base, fontSize=7.4, leading=9.2),
        "cellb": ParagraphStyle("cellb", parent=base, fontSize=7.4, leading=9.2, fontName="Helvetica-Bold"),
        "h1": ParagraphStyle("h1", parent=base, fontName="Helvetica-Bold", fontSize=20, leading=24, spaceAfter=4),
        "h2": ParagraphStyle("h2", parent=base, fontName="Helvetica-Bold", fontSize=12.5, leading=16, spaceBefore=10, spaceAfter=6, textColor=INK),
        "h3": ParagraphStyle("h3", parent=base, fontName="Helvetica-Bold", fontSize=9.6, leading=12, spaceBefore=6, spaceAfter=3),
        "eyebrow": ParagraphStyle("eyebrow", parent=base, fontName="Helvetica-Bold", fontSize=7.5, textColor=CYAN, leading=10),
        "notetext": ParagraphStyle("notetext", parent=base, fontSize=8, leading=10.5, textColor=colors.HexColor("#7C2D12")),
        "note": ParagraphStyle("note", parent=base, fontSize=8, leading=10.5, textColor=colors.HexColor("#7C2D12"), backColor=colors.HexColor("#FFF7ED"),
                               borderColor=colors.HexColor("#FDBA74"), borderWidth=0.6, borderPadding=6, alignment=TA_LEFT),
    }


def _esc(s) -> str:
    if s is None:
        return "—"
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def _img(key: str | None, max_w: float, max_h: float):
    st = get_storage()
    if not key or not st.exists(key):
        return None
    from PIL import Image as PILImage

    data = st.read_bytes(key)
    with PILImage.open(io.BytesIO(data)) as im:
        w, h = im.size
        if max(w, h) > 1800:
            s = 1800 / max(w, h)
            im = im.convert("RGB").resize((int(w * s), int(h * s)))
            buf = io.BytesIO()
            im.save(buf, format="JPEG", quality=85)
            data = buf.getvalue()
            w, h = im.size
    s = min(max_w / w, max_h / h)
    return RLImage(io.BytesIO(data), width=w * s, height=h * s)


def _table(rows, widths, header=True, zebra=True):
    t = Table(rows, colWidths=widths, repeatRows=1 if header else 0)
    style = [
        ("FONT", (0, 0), (-1, -1), "Helvetica", 7.4),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LINEBELOW", (0, 0), (-1, -1), 0.3, LINE),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ]
    if header:
        style += [("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#0F172A")), ("TEXTCOLOR", (0, 0), (-1, 0), colors.white), ("FONT", (0, 0), (-1, 0), "Helvetica-Bold", 7.4)]
    if zebra:
        for r in range(1 if header else 0, len(rows)):
            if r % 2 == 0:
                style.append(("BACKGROUND", (0, r), (-1, r), colors.HexColor("#F6F8FB")))
    t.setStyle(TableStyle(style))
    return t


def _note(text: str, S, width: float) -> Table:
    t = Table([[Paragraph(text, S["notetext"])]], colWidths=[width])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#FFF7ED")), ("BOX", (0, 0), (-1, -1), 0.6, colors.HexColor("#FDBA74")),
                           ("LEFTPADDING", (0, 0), (-1, -1), 8), ("RIGHTPADDING", (0, 0), (-1, -1), 8), ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 6)]))
    return t


def _verdict_cell(v: str, S) -> Paragraph:
    c = VERDICT_COL.get(v, MUTED)
    return Paragraph(f'<font color="{c.hexval()}"><b>{_esc(v)}</b></font>', S["cell"])


def generate_pdf_report(db: Session, version_id: str) -> Report:
    v = db.get(InspectionVersion, version_id)
    insp = db.get(Inspection, v.inspection_id)
    findings = db.scalars(select(Finding).where(Finding.version_id == version_id).order_by(Finding.seq)).all()
    evid = db.scalars(select(EvidenceAsset).where(EvidenceAsset.version_id == version_id)).all()
    ev_by_finding: dict[str, list[EvidenceAsset]] = {}
    for e in evid:
        if e.finding_id:
            ev_by_finding.setdefault(e.finding_id, []).append(e)
    annotated = next((e for e in evid if e.kind == "annotated_photo"), None)
    reg_overlay = next((e for e in evid if e.kind == "registration_overlay"), None)
    S = _styles()
    now = datetime.now(timezone.utc)
    buf = io.BytesIO()
    W, H = A4
    margin = 16 * mm

    def on_page(c, doc):
        c.saveState()
        c.setFillColor(colors.HexColor("#0B1220"))
        c.rect(0, H - 13 * mm, W, 13 * mm, stroke=0, fill=1)
        c.setFillColor(colors.HexColor("#22D3EE"))
        p = c.beginPath()
        p.moveTo(margin, H - 4 * mm)
        p.lineTo(margin + 7 * mm, H - 4 * mm)
        p.lineTo(margin + 3.5 * mm, H - 10 * mm)
        p.close()
        c.drawPath(p, stroke=0, fill=1)
        c.setFillColor(colors.white)
        c.setFont("Helvetica-Bold", 10)
        c.drawString(margin + 10 * mm, H - 8.6 * mm, "EAGLE EYE")
        c.setFont("Helvetica", 7.5)
        c.setFillColor(colors.HexColor("#94A3B8"))
        c.drawString(margin + 33 * mm, H - 8.6 * mm, "Drawing-aware cabinet inspection  ·  OpHackers")
        c.drawRightString(W - margin, H - 8.6 * mm, f"{insp.code}  ·  v{v.version_no}  ·  {insp.cabinet_id}")
        c.setFillColor(MUTED)
        c.setFont("Helvetica", 7)
        c.drawString(margin, 9 * mm, f"Generated {now.strftime('%Y-%m-%d %H:%M UTC')} · Supports inspection and human review — not a certificate of compliance.")
        c.drawRightString(W - margin, 9 * mm, f"Page {doc.page}")
        if insp.is_demo:
            c.setFillColor(colors.HexColor("#D97706"))
            c.setFont("Helvetica-Bold", 7)
            c.drawCentredString(W / 2, 13.5 * mm, "DEMONSTRATION FIXTURE — SYNTHETIC INPUT DATA, NOT A REAL CABINET")
        c.restoreState()

    doc = SimpleDocTemplate(buf, pagesize=A4, leftMargin=margin, rightMargin=margin, topMargin=20 * mm, bottomMargin=18 * mm,
                            title=f"EAGLE EYE report {insp.code} v{v.version_no}", author="EAGLE EYE", subject="Cabinet inspection report")
    cw = W - 2 * margin
    story = []
    eff = {"PASS": 0, "FAIL": 0, "UNCERTAIN": 0, "WAIVED": 0}
    for f in findings:
        eff[effective_verdict(f)] = eff.get(effective_verdict(f), 0) + 1
    summ = v.summary or {}
    story.append(Paragraph("INSPECTION REPORT", S["eyebrow"]))
    story.append(Paragraph(_esc(insp.title), S["h1"]))
    story.append(Paragraph(f"Cabinet <b>{_esc(insp.cabinet_id)}</b> · Inspection <b>{insp.code}</b> · Version <b>{v.version_no}</b> ({_esc(v.label)})", S["base"]))
    story.append(Spacer(1, 6))
    story.append(_note(
        "This report records automated observations and rule-based verdicts with their photographic evidence, together with any human review decisions. "
        "It supports inspection and quality review; it does <b>not</b> certify the cabinet as compliant. UNCERTAIN items require human review and are counted "
        "neither as passes nor as failures.", S, cw))
    if insp.is_demo:
        story.append(Spacer(1, 4))
        story.append(_note("The inputs of this inspection are bundled SYNTHETIC demonstration fixtures (computer-generated photo, drawing and list). "
                           "The processing and verdicts were produced by the live pipeline on those inputs.", S, cw))
    story.append(Spacer(1, 8))
    kpi = [[Paragraph(f'<font size="17" color="{VERDICT_COL[k].hexval()}"><b>{summ.get(k.lower(), 0)}</b></font><br/><font size="7" color="#5B6577">{k} (machine)</font>', S["base"]) for k in ("PASS", "FAIL", "UNCERTAIN")]
           + [Paragraph(f'<font size="17"><b>{summ.get("total", 0)}</b></font><br/><font size="7" color="#5B6577">FINDINGS</font>', S["base"])]]
    kt = Table(kpi, colWidths=[cw / 4] * 4)
    kt.setStyle(TableStyle([("BOX", (0, 0), (-1, -1), 0.5, LINE), ("INNERGRID", (0, 0), (-1, -1), 0.5, LINE), ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 6), ("LEFTPADDING", (0, 0), (-1, -1), 8)]))
    story.append(kt)
    story.append(Spacer(1, 4))
    story.append(Paragraph(f"After human review: PASS {eff['PASS']} · FAIL {eff['FAIL']} · UNCERTAIN {eff['UNCERTAIN']} · WAIVED {eff.get('WAIVED', 0)}", S["small"]))

    story.append(Paragraph("Case and processing", S["h2"]))
    reg = v.registration or {}
    dmc = db.get(ModelConfiguration, v.detector_config_id) if v.detector_config_id else None
    omc = db.get(ModelConfiguration, v.ocr_config_id) if v.ocr_config_id else None
    q = (v.preprocessing or {}).get("quality", {})
    started = v.started_at.replace(tzinfo=timezone.utc) if v.started_at and v.started_at.tzinfo is None else v.started_at
    run_s = (v.duration_ms / 1000) if v.duration_ms else ((now - started).total_seconds() if started else 0.0)
    rows = [
        ["Site / facility", _esc(insp.site), "Inspection reference", _esc(insp.reference)],
        ["Inspector", _esc(insp.inspector), "Project / customer", _esc(insp.project_ref)],
        ["Created", _esc(iso(insp.created_at))[:19], "Run completed", _esc(iso(v.completed_at))[:19] if v.completed_at else "report generated as the final pipeline stage"],
        ["Processing time", f"{run_s:.1f} s" + ("" if v.completed_at else " (up to report stage)"), "Image quality", f"{q.get('rating', '—')} (sharpness {q.get('sharpness_laplacian_var', '—')})"],
        ["Detector", _esc(dmc.name if dmc else "unavailable") + (f" ({dmc.params.get('kind')}, {dmc.params.get('device')})" if dmc else ""), "OCR engine", _esc(omc.name if omc else "unavailable")],
        ["Registration", f"{_esc(reg.get('status'))} {('· ' + reg.get('method')) if reg.get('method') else ''}", "Checks", _esc(", ".join((v.config or {}).get("checks", [])) or "default")],
    ]
    t = Table([[Paragraph(f"<font color='#5B6577'>{a}</font>", S["cell"]), Paragraph(str(b), S["cell"]), Paragraph(f"<font color='#5B6577'>{c}</font>", S["cell"]), Paragraph(str(d), S["cell"])] for a, b, c, d in rows],
              colWidths=[cw * 0.16, cw * 0.34, cw * 0.16, cw * 0.34])
    t.setStyle(TableStyle([("LINEBELOW", (0, 0), (-1, -1), 0.3, LINE), ("VALIGN", (0, 0), (-1, -1), "TOP")]))
    story.append(t)
    story.append(Paragraph("Input files", S["h3"]))
    arows = [["Kind", "File", "Size", "SHA-256"]]
    for a in sorted(v.assets, key=lambda a: a.kind):
        arows.append([a.kind, Paragraph(_esc(a.original_filename), S["cell"]), f"{a.size_bytes / 1024:.0f} KB", Paragraph(f"<font face='Courier' size='6.5'>{a.sha256[:32]}…</font>", S["cell"])])
    story.append(_table(arows, [cw * 0.14, cw * 0.38, cw * 0.1, cw * 0.38]))

    if annotated:
        im = _img(annotated.storage_key, cw, 120 * mm)
        if im:
            story.append(KeepTogether([Paragraph("Annotated photograph", S["h2"]), im,
                                       Paragraph("Boxes are coloured by machine verdict; dashed boxes mark expected positions where no observation was associated.", S["small"])]))
    if reg_overlay:
        im = _img(reg_overlay.storage_key, cw, 95 * mm)
        if im:
            story.append(KeepTogether([Paragraph("Registered GA drawing overlay", S["h3"]), im]))

    story.append(PageBreak())
    story.append(Paragraph("Findings", S["h2"]))
    frows = [["#", "Check", "Zone", "Subject", "Expected", "Observed", "Machine", "After review"]]
    for f in findings:
        ev = effective_verdict(f)
        frows.append([str(f.seq), Paragraph(_esc(f.check_type.replace("_", " ")), S["cell"]), _esc(f.zone_code), Paragraph(_esc(f.subject), S["cell"]),
                      Paragraph(_esc(f.expected_value), S["cell"]), Paragraph(_esc(f.observed_value), S["cell"]), _verdict_cell(f.verdict, S),
                      _verdict_cell(ev, S) if f.reviews else Paragraph("<font color='#5B6577'>unreviewed</font>", S["cell"])])
    story.append(_table(frows, [cw * 0.05, cw * 0.14, cw * 0.07, cw * 0.14, cw * 0.17, cw * 0.17, cw * 0.12, cw * 0.14]))

    story.append(Paragraph("Evidence for FAIL and UNCERTAIN findings", S["h2"]))
    shown = 0
    for f in findings:
        if f.verdict == "PASS" and not f.reviews:
            continue
        evs = ev_by_finding.get(f.id, [])
        ann = next((e for e in evs if e.kind == "finding_crop_annotated"), None) or next((e for e in evs if e.kind == "finding_crop"), None)
        im = _img(ann.storage_key, 55 * mm, 45 * mm) if ann else None
        conf = f.confidences or {}
        conf_txt = ", ".join(f"{k}: {conf[k]}" for k in ("detector", "ocr", "edit_distance", "text_similarity", "color_fraction") if conf.get(k) is not None) or "—"
        txt = [
            Paragraph(f"<b>#{f.seq} · {_esc(f.check_type.replace('_', ' '))} · {_esc(f.subject)}</b> &nbsp; " + f'<font color="{VERDICT_COL[f.verdict].hexval()}"><b>{f.verdict}</b></font>', S["base"]),
            Paragraph(f"Expected <b>{_esc(f.expected_value)}</b> · Observed <b>{_esc(f.observed_value)}</b>" + (f" (raw OCR '{_esc(f.observed_raw)}')" if f.observed_raw and f.observed_raw != f.observed_value else ""), S["cell"]),
            Paragraph(f"Rule <font face='Courier'>{_esc(f.rule)}</font> · Confidence sources: {_esc(conf_txt)}", S["cell"]),
            Paragraph(_esc(f.explanation), S["cell"]),
        ]
        if f.review_reasons:
            txt.append(Paragraph("Review reasons: " + _esc(", ".join(f.review_reasons)), S["small"]))
        for r in f.reviews:
            txt.append(Paragraph(f"Review ({_esc(r.reviewer)}, {iso(r.created_at)[:16]}): <b>{_esc(r.action)}</b>" + (f" → {r.resulting_verdict}" if r.resulting_verdict else "")
                                 + (f" · corrected value '{_esc(r.corrected_value)}'" if r.corrected_value else "") + (f" · reason: {_esc(r.reason)}" if r.reason else "") + (f" · {_esc(r.notes)}" if r.notes else ""), S["small"]))
        if not im:
            err = next((e.error for e in evs if e.error), "no image evidence")
            txt.append(Paragraph(f"<i>No crop: {_esc(err)}</i>", S["small"]))
        row = Table([[im or Paragraph("", S["cell"]), txt]], colWidths=[58 * mm, cw - 58 * mm])
        row.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LINEBELOW", (0, 0), (-1, -1), 0.4, LINE), ("BOTTOMPADDING", (0, 0), (-1, -1), 7)]))
        story.append(KeepTogether(row))
        shown += 1
    if not shown:
        story.append(Paragraph("No FAIL or UNCERTAIN findings in this version.", S["base"]))

    if v.parent_version_id:
        cmp_ = db.scalar(select(VersionComparison).where(VersionComparison.to_version_id == v.id))
        if cmp_:
            story.append(Paragraph(f"Reinspection comparison (v{cmp_.summary.get('from_version')} → v{cmp_.summary.get('to_version')})", S["h2"]))
            crow = [["Category", "Count"]] + [[k.replace("_", " "), str(n)] for k, n in cmp_.summary.get("counts", {}).items()]
            story.append(_table(crow, [cw * 0.5, cw * 0.15]))
            story.append(Paragraph("A previous discrepancy counts as resolved only if the new run verified it as PASS. Earlier versions are preserved unchanged.", S["small"]))

    story.append(Paragraph("Known limitations", S["h2"]))
    lims = list(get_detector().status().get("limitations", []))
    lims += [
        "Registration uses a planar homography; component depth (parallax) is not modelled, so strongly oblique photographs reduce position accuracy.",
        "OCR confidences are engine-reported scores, not calibrated probabilities. No combined confidence score is computed.",
        "Wire-colour verification, where enabled, is experimental and depends on lighting and camera white balance.",
        "Absence of a FAIL in a region that could not be inspected is not evidence of conformity — such items are reported as UNCERTAIN.",
    ]
    for li in lims:
        story.append(Paragraph(f"• {_esc(li)}", S["cell"]))
    doc.build(story, onFirstPage=on_page, onLaterPages=on_page)
    data = buf.getvalue()
    st = get_storage()
    key = st.make_key("inspections", insp.id, v.id, "reports", ext="pdf")
    sha, size = st.put_bytes(key, data)
    pages = data.count(b"/Type /Page") - data.count(b"/Type /Pages")
    rep = Report(inspection_id=insp.id, version_id=v.id, format="pdf", storage_key=key, filename=f"EAGLE-EYE_{insp.code}_v{v.version_no}.pdf", size_bytes=size, sha256=sha, pages=max(1, pages))
    db.add(rep)
    db.flush()
    audit(db, "report_generated", "report", rep.id, insp.id, {"format": "pdf", "version_no": v.version_no, "pages": rep.pages})
    db.flush()
    return rep
