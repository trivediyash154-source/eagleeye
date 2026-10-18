"""Maintenance commands.

    python -m app.maintenance purge [--dry-run]
        Deletes regenerable thumbnails older than EAGLEEYE_TEMP_RETENTION_HOURS and stale
        ``*.part`` upload fragments. Inputs, evidence, reports and inspection versions are
        NEVER deleted automatically (retention policy: kept until explicitly removed).

    python -m app.maintenance verify
        Recomputes SHA-256 hashes of stored inputs and evidence and reports mismatches
        or missing files (integrity check).
"""
from __future__ import annotations

import argparse
import time

from sqlalchemy import select

from .core.config import get_settings
from .core.db import SessionLocal
from .models import EvidenceAsset, InputAsset
from .storage.local import get_storage, sha256_file


def purge(dry_run: bool) -> int:
    s = get_settings()
    root = get_storage().root
    cutoff = time.time() - s.temp_retention_hours * 3600
    n = 0
    for p in list(root.rglob("*.thumb.jpg")) + list(root.rglob("*.part")):
        if p.stat().st_mtime < cutoff:
            n += 1
            print(("would delete " if dry_run else "deleted ") + str(p.relative_to(root)))
            if not dry_run:
                p.unlink(missing_ok=True)
    print(f"{n} temporary file(s) {'eligible' if dry_run else 'removed'}")
    return 0


def verify() -> int:
    st = get_storage()
    bad = 0
    with SessionLocal() as db:
        rows = [(a.storage_key, a.sha256, f"input {a.id}") for a in db.scalars(select(InputAsset))]
        rows += [(e.storage_key, e.sha256, f"evidence {e.id}") for e in db.scalars(select(EvidenceAsset)) if e.storage_key and e.sha256]
    seen = set()
    for key, sha, label in rows:
        if key in seen:
            continue
        seen.add(key)
        if not st.exists(key):
            print(f"MISSING  {label}  {key}")
            bad += 1
        elif sha256_file(st.path_for(key)) != sha:
            print(f"MISMATCH {label}  {key}")
            bad += 1
    print(f"checked {len(seen)} file(s), {bad} problem(s)")
    return 1 if bad else 0


def main() -> None:
    ap = argparse.ArgumentParser(prog="python -m app.maintenance")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("purge")
    p.add_argument("--dry-run", action="store_true")
    sub.add_parser("verify")
    a = ap.parse_args()
    raise SystemExit(purge(a.dry_run) if a.cmd == "purge" else verify())


if __name__ == "__main__":
    main()
