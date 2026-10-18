from __future__ import annotations

import hashlib
import json

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.config import get_settings
from ..models import AuditEvent, Finding, ModelConfiguration

VERDICT_ACTIONS = {
    "confirm": None,  # agrees with the machine verdict
    "resolve_pass": "PASS",
    "resolve_fail": "FAIL",
    "false_positive": "PASS",
    "waive": "WAIVED",
}


def audit(db: Session, event_type: str, entity_type: str, entity_id: str, inspection_id: str | None = None, details: dict | None = None,
          message: str | None = None, actor: str | None = None) -> AuditEvent:
    ev = AuditEvent(actor=actor or "system", event_type=event_type, entity_type=entity_type, entity_id=entity_id, inspection_id=inspection_id,
                    details=details or {}, message=message)
    db.add(ev)
    return ev


def reviewer() -> str:
    return get_settings().reviewer_identity


def effective_verdict(f: Finding) -> str:
    """Verdict after human review (latest decision that sets a verdict); machine verdict otherwise."""
    for r in reversed(f.reviews or []):
        if r.resulting_verdict:
            return r.resulting_verdict
    return f.verdict


def review_status(f: Finding) -> str:
    if not f.reviews:
        return "unreviewed"
    return "reviewed"


def upsert_model_config(db: Session, kind: str, name: str, params: dict) -> ModelConfiguration:
    fp = hashlib.sha256(json.dumps({"kind": kind, "name": name, "params": params}, sort_keys=True, default=str).encode()).hexdigest()
    existing = db.scalar(select(ModelConfiguration).where(ModelConfiguration.fingerprint == fp))
    if existing:
        return existing
    mc = ModelConfiguration(kind=kind, name=name, fingerprint=fp, params=params)
    db.add(mc)
    db.flush()
    return mc
