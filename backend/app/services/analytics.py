"""Analytics computed from persisted records only.

Basis: verdict/quality statistics use the LATEST COMPLETED version of each inspection (so a
re-inspected cabinet is not double counted); activity/volume statistics use every run.
No accuracy metric is reported: there is no validated real-world ground-truth dataset.
"""
from __future__ import annotations

from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from ..core.util import as_aware, iso
from ..models import AuditEvent, Detection, EvidenceAsset, Finding, Inspection, InspectionVersion, VersionComparison
from .common import effective_verdict

LABEL_CHECKS = {"device_label", "ferrule_label"}


def _parse_date(s: str | None, end: bool = False) -> datetime | None:
    if not s:
        return None
    d = datetime.fromisoformat(s)
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    if end and len(s) <= 10:
        d = d + timedelta(days=1)
    return d


def _scope(db: Session, dataset: str, date_from: str | None, date_to: str | None):
    q = select(Inspection).options(selectinload(Inspection.versions))
    if dataset == "real":
        q = q.where(Inspection.is_demo.is_(False))
    elif dataset == "demo":
        q = q.where(Inspection.is_demo.is_(True))
    inspections = db.scalars(q).all()
    df, dt = _parse_date(date_from), _parse_date(date_to, end=True)
    runs = [v for i in inspections for v in i.versions if (df is None or as_aware(v.created_at) >= df) and (dt is None or as_aware(v.created_at) < dt)]
    latest = []
    for i in inspections:
        done = [v for v in i.versions if v.status == "completed"]
        if done:
            lv = max(done, key=lambda v: v.version_no)
            if (df is None or as_aware(lv.created_at) >= df) and (dt is None or as_aware(lv.created_at) < dt):
                latest.append(lv)
    return inspections, runs, latest


def overview(db: Session, dataset: str = "all", date_from: str | None = None, date_to: str | None = None) -> dict:
    inspections, runs, latest = _scope(db, dataset, date_from, date_to)
    latest_ids = [v.id for v in latest]
    findings = db.scalars(select(Finding).options(selectinload(Finding.reviews)).where(Finding.version_id.in_(latest_ids))).all() if latest_ids else []
    eff = Counter(effective_verdict(f) for f in findings)
    machine = Counter(f.verdict for f in findings)
    completed_runs = [v for v in runs if v.status == "completed"]
    durations = [v.duration_ms for v in completed_runs if v.duration_ms]
    needs_review_versions = set()
    queue = 0
    for f in findings:
        ev = effective_verdict(f)
        if ev == "UNCERTAIN" or (f.verdict == "FAIL" and not f.reviews):
            needs_review_versions.add(f.version_id)
            queue += 1
    # evidence completeness: findings that should carry an image crop
    crop_expected = [f for f in findings if f.check_type != "drawing_alignment"]
    with_crop = set()
    if latest_ids:
        for fid, in db.execute(select(EvidenceAsset.finding_id).where(EvidenceAsset.version_id.in_(latest_ids), EvidenceAsset.kind == "finding_crop", EvidenceAsset.storage_key.is_not(None))):
            with_crop.add(fid)
    evidence_complete = sum(1 for f in crop_expected if f.id in with_crop)
    # volume by day (all runs)
    by_day: dict[str, dict] = defaultdict(lambda: {"runs": 0, "completed": 0, "failed": 0})
    for v in runs:
        d = as_aware(v.created_at).date().isoformat()
        by_day[d]["runs"] += 1
        if v.status == "completed":
            by_day[d]["completed"] += 1
        elif v.status == "failed":
            by_day[d]["failed"] += 1
    volume = [{"date": k, **val} for k, val in sorted(by_day.items())]
    # categories
    by_check: dict[str, Counter] = defaultdict(Counter)
    for f in findings:
        by_check[f.check_type][effective_verdict(f)] += 1
    categories = [{"check_type": k, **dict(c)} for k, c in sorted(by_check.items())]
    # mismatch patterns from recorded edit operations
    subs = Counter()
    subjects = Counter()
    zones_review = Counter()
    unreadable = 0
    label_total = 0
    for f in findings:
        if f.check_type in LABEL_CHECKS:
            label_total += 1
            if f.rule in ("no_readable_text",):
                unreadable += 1
            comp = (f.details or {}).get("comparison") or {}
            for e in comp.get("edits", []) or []:
                if e.get("op") == "substitute":
                    subs[f"{e['expected']}→{e['observed']}"] += 1
            if effective_verdict(f) in ("FAIL", "UNCERTAIN"):
                subjects[f"{f.check_type}:{f.subject}"] += 1
        if effective_verdict(f) == "UNCERTAIN" and f.zone_code:
            zones_review[f.zone_code] += 1
    reg = Counter((v.registration or {}).get("status", "not_run") for v in completed_runs)
    det_counts = Counter()
    if latest_ids:
        for name, in db.execute(select(Detection.class_name).where(Detection.version_id.in_(latest_ids), Detection.above_threshold.is_(True))):
            det_counts[name] += 1
    # duration histogram (seconds)
    buckets = [10, 20, 30, 45, 60, 90, 120, 180, 300]
    hist = []
    prev = 0
    for b in buckets + [None]:
        n = sum(1 for d in durations if d / 1000 >= prev and (b is None or d / 1000 < b))
        hist.append({"from_s": prev, "to_s": b, "count": n})
        prev = b if b else prev
    # reinspection outcomes
    reinsp = Counter()
    insp_ids = [i.id for i in inspections]
    if insp_ids:
        for cmp_ in db.scalars(select(VersionComparison).where(VersionComparison.inspection_id.in_(insp_ids))):
            for k, n in (cmp_.summary or {}).get("counts", {}).items():
                reinsp[k] += n
    with_reinspection = sum(1 for i in inspections if len(i.versions) > 1)
    last_ok = max((as_aware(v.completed_at) for v in completed_runs if v.completed_at), default=None)
    return {
        "basis": {
            "dataset": dataset, "date_from": date_from, "date_to": date_to,
            "verdict_statistics": "latest completed version per inspection", "activity_statistics": "all runs",
            "sample": {"inspections": len(inspections), "runs": len(runs), "completed_runs": len(completed_runs), "findings": len(findings)},
            "demo_inspections": sum(1 for i in inspections if i.is_demo),
        },
        "kpis": {
            "total_inspections": len(inspections),
            "completed_runs": len(completed_runs),
            "failed_runs": sum(1 for v in runs if v.status == "failed"),
            "inspections_requiring_review": len(needs_review_versions),
            "confirmed_discrepancies": eff.get("FAIL", 0),
            "verified_items": eff.get("PASS", 0),
            "uncertain_items": eff.get("UNCERTAIN", 0),
            "waived_items": eff.get("WAIVED", 0),
            "avg_processing_ms": int(sum(durations) / len(durations)) if durations else None,
            "median_processing_ms": int(sorted(durations)[len(durations) // 2]) if durations else None,
            "reinspection_rate": round(with_reinspection / len(inspections), 3) if inspections else None,
            "evidence_completeness": round(evidence_complete / len(crop_expected), 3) if crop_expected else None,
            "review_queue_size": queue,
            "last_successful_inspection_at": iso(last_ok),
        },
        "machine_verdicts": dict(machine),
        "effective_verdicts": dict(eff),
        "volume_by_day": volume,
        "finding_categories": categories,
        "substitution_patterns": [{"pattern": k, "count": n} for k, n in subs.most_common(12)],
        "repeated_mismatches": [{"subject": k, "count": n} for k, n in subjects.most_common(12) if n > 0],
        "zones_requiring_review": [{"zone": k, "count": n} for k, n in zones_review.most_common(12)],
        "ocr_unreadable": {"unreadable": unreadable, "label_findings": label_total, "rate": round(unreadable / label_total, 3) if label_total else None},
        "registration_outcomes": dict(reg),
        "detections_by_class": dict(det_counts.most_common()),
        "duration_histogram": hist,
        "reinspection_outcomes": dict(reinsp),
        "accuracy": {"measured": False, "note": "No validated real-world ground-truth dataset exists, so model accuracy is not reported as a measured metric."},
    }


def activity(db: Session, limit: int = 20, dataset: str = "all") -> list[dict]:
    q = select(AuditEvent).where(AuditEvent.event_type.in_(["run_completed", "run_failed", "run_started", "inspection_created", "review_recorded", "reinspection_created", "report_generated", "run_cancelled"])).order_by(AuditEvent.created_at.desc()).limit(limit * 3)
    out = []
    cache: dict[str, Inspection | None] = {}
    for ev in db.scalars(q):
        if ev.inspection_id not in cache:
            cache[ev.inspection_id] = db.get(Inspection, ev.inspection_id) if ev.inspection_id else None
        insp = cache[ev.inspection_id]
        if insp is None or (dataset == "real" and insp.is_demo) or (dataset == "demo" and not insp.is_demo):
            continue
        d = ev.details or {}
        ver = None
        if ev.entity_type == "version":
            ver = db.get(InspectionVersion, ev.entity_id)
        out.append({
            "id": ev.id, "event_type": ev.event_type, "created_at": iso(ev.created_at), "actor": ev.actor, "inspection_id": insp.id, "inspection_code": insp.code,
            "cabinet_id": insp.cabinet_id, "is_demo": insp.is_demo, "version_no": ver.version_no if ver else d.get("version_no"),
            "status": ver.status if ver else None, "summary": d.get("summary"), "duration_ms": d.get("duration_ms"), "details": d,
        })
        if len(out) >= limit:
            break
    return out


TIER_INFO = {
    1: "Machine FAIL awaiting human confirmation",
    2: "Registration failed — position-based checks of the whole run depend on it",
    3: "UNCERTAIN: conflicting or ambiguous evidence (confusable characters, ambiguous association, partial read)",
    4: "UNCERTAIN: missing or unreadable evidence (no text, weak detection, unsupported class)",
}


def review_queue(db: Session, inspection_id: str | None = None, reason: str | None = None, check_type: str | None = None, sort: str = "tier", dataset: str = "all") -> dict:
    insps = db.scalars(select(Inspection).options(selectinload(Inspection.versions))).all()
    latest = {}
    for i in insps:
        if inspection_id and i.id != inspection_id:
            continue
        if (dataset == "real" and i.is_demo) or (dataset == "demo" and not i.is_demo):
            continue
        done = [v for v in i.versions if v.status == "completed"]
        if done:
            latest[max(done, key=lambda v: v.version_no).id] = i
    if not latest:
        return {"items": [], "total": 0, "tiers": TIER_INFO, "reason_counts": {}}
    findings = db.scalars(select(Finding).options(selectinload(Finding.reviews)).where(Finding.version_id.in_(list(latest)))).all()
    items = []
    reason_counts = Counter()
    vnos = {vid: v.version_no for i in latest.values() for v in i.versions for vid in [v.id]}
    for f in findings:
        ev = effective_verdict(f)
        reasons = list(f.review_reasons or [])
        if f.verdict == "FAIL" and not f.reviews:
            reasons.append("unreviewed_fail")
        elif ev != "UNCERTAIN":
            continue
        if not reasons:
            reasons.append("uncertain")
        if reason and reason not in reasons:
            continue
        if check_type and f.check_type != check_type:
            continue
        if "unreviewed_fail" in reasons:
            tier = 1
        elif f.check_type == "drawing_alignment":
            tier = 2
        elif set(reasons) & {"confusable_characters", "ambiguous_association", "possible_partial_read", "near_match", "conflicting_observations"}:
            tier = 3
        else:
            tier = 4
        for r in reasons:
            reason_counts[r] += 1
        insp = latest[f.version_id]
        items.append({
            "finding_id": f.id, "inspection_id": insp.id, "inspection_code": insp.code, "cabinet_id": insp.cabinet_id, "is_demo": insp.is_demo,
            "version_id": f.version_id, "version_no": vnos.get(f.version_id), "seq": f.seq, "check_type": f.check_type, "zone_code": f.zone_code,
            "subject": f.subject, "expected_value": f.expected_value, "observed_value": f.observed_value, "verdict": f.verdict, "effective_verdict": ev,
            "reasons": sorted(set(reasons)), "tier": tier, "tier_label": TIER_INFO[tier], "explanation": f.explanation, "created_at": iso(f.created_at),
            "review_count": len(f.reviews),
        })
    if sort == "newest":
        items.sort(key=lambda x: x["created_at"], reverse=True)
    elif sort == "inspection":
        items.sort(key=lambda x: (x["inspection_code"], x["seq"]))
    else:
        items.sort(key=lambda x: (x["tier"], x["inspection_code"], x["seq"]))
    return {"items": items, "total": len(items), "tiers": TIER_INFO, "reason_counts": dict(reason_counts),
            "ordering": "tier ascending (tier definitions provided), then inspection and finding number; no numeric urgency score is computed"}
