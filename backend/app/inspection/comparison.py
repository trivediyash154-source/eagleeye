"""Compare findings of two inspection versions by stable finding keys.

The earlier version's *effective* verdict (after human review) is compared with the new
version's machine verdict. A discrepancy is "resolved" only when the new run positively
verifies the item (PASS); an UNCERTAIN re-check never closes a FAIL.
"""
from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import Finding, InspectionVersion, VersionComparison
from ..services.common import audit, effective_verdict

CATEGORY_INFO = {
    "resolved": "Previously failed or uncertain-as-fail item now verified PASS",
    "persistent": "Discrepancy still present",
    "unconfirmed": "Previously failed item could not be re-verified (UNCERTAIN) — remains open",
    "new_discrepancy": "Item that passed (or was not checked) now fails",
    "still_uncertain": "Item remains UNCERTAIN",
    "clarified_pass": "Previously uncertain item now verified PASS",
    "clarified_fail": "Previously uncertain item now confirmed FAIL",
    "regressed_to_uncertain": "Previously passing item is now UNCERTAIN",
    "unchanged_pass": "Item passed in both versions",
    "waived": "Item was waived with a recorded reason",
    "new_check": "Item checked only in the newer version",
    "not_rechecked": "Item checked only in the earlier version",
}


def categorize(prev: str | None, new: str | None) -> str:
    if prev is None:
        return "new_discrepancy" if new == "FAIL" else "new_check"
    if new is None:
        return "not_rechecked"
    if prev == "WAIVED":
        return "waived"
    table = {
        ("FAIL", "PASS"): "resolved", ("FAIL", "FAIL"): "persistent", ("FAIL", "UNCERTAIN"): "unconfirmed",
        ("PASS", "FAIL"): "new_discrepancy", ("PASS", "PASS"): "unchanged_pass", ("PASS", "UNCERTAIN"): "regressed_to_uncertain",
        ("UNCERTAIN", "PASS"): "clarified_pass", ("UNCERTAIN", "FAIL"): "clarified_fail", ("UNCERTAIN", "UNCERTAIN"): "still_uncertain",
    }
    return table.get((prev, new), "still_uncertain")


def compare_versions(db: Session, from_version_id: str, to_version_id: str) -> VersionComparison:
    a = db.get(InspectionVersion, from_version_id)
    b = db.get(InspectionVersion, to_version_id)
    fa = {f.finding_key: f for f in db.scalars(select(Finding).where(Finding.version_id == from_version_id))}
    fb = {f.finding_key: f for f in db.scalars(select(Finding).where(Finding.version_id == to_version_id))}
    items = []
    summary: dict[str, int] = {k: 0 for k in CATEGORY_INFO}
    for key in sorted(set(fa) | set(fb)):
        x, y = fa.get(key), fb.get(key)
        pv = effective_verdict(x) if x else None
        nv = y.verdict if y else None
        cat = categorize(pv, nv)
        summary[cat] += 1
        ref = y or x
        items.append({
            "finding_key": key, "check_type": ref.check_type, "subject": ref.subject, "zone_code": ref.zone_code, "category": cat,
            "from": {"finding_id": x.id, "seq": x.seq, "machine_verdict": x.verdict, "effective_verdict": pv, "observed": x.observed_value} if x else None,
            "to": {"finding_id": y.id, "seq": y.seq, "verdict": nv, "observed": y.observed_value} if y else None,
            "expected": ref.expected_value,
        })
    existing = db.scalar(select(VersionComparison).where(VersionComparison.from_version_id == from_version_id, VersionComparison.to_version_id == to_version_id))
    if existing:
        db.delete(existing)
        db.flush()
    cmp_ = VersionComparison(inspection_id=b.inspection_id, from_version_id=from_version_id, to_version_id=to_version_id,
                             summary={"from_version": a.version_no, "to_version": b.version_no, "counts": {k: v for k, v in summary.items() if v}}, items=items)
    db.add(cmp_)
    db.flush()
    audit(db, "versions_compared", "comparison", cmp_.id, b.inspection_id, {"from": a.version_no, "to": b.version_no, "counts": cmp_.summary["counts"]})
    db.flush()
    return cmp_
