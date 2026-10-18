"""OCR string normalisation.

Normalisation is deterministic and independent of the expected value: the observed string is
never rewritten to look like what the specification expects. Every step is recorded so the
raw observation and each transformation remain auditable.

Visually-confusable characters (0/O, 1/I, 8/B, ...) are NOT substituted in the normalised
value. Instead :func:`confusable_key` provides a comparison key used only to *classify* a
difference as "possibly an OCR confusion" (which leads to UNCERTAIN, not PASS).
"""
from __future__ import annotations

import re

DASHES = "‐‑‒–—―−﹣－_~"
EDGE_JUNK = " .,;:'\"|`!()[]{}"

# pairs of characters that OCR engines commonly confuse on printed labels
CONFUSABLE_GROUPS: list[set[str]] = [
    {"0", "O", "D", "Q"},
    {"1", "I", "L", "7"},
    {"2", "Z"},
    {"5", "S"},
    {"8", "B"},
    {"6", "G"},
]
_CANON = {}
for grp in CONFUSABLE_GROUPS:
    rep = sorted(grp)[0]
    for ch in grp:
        _CANON[ch] = rep


def normalize(raw: str, remove_spaces: bool = True) -> tuple[str, list[dict]]:
    steps: list[dict] = []
    s = raw

    def step(op: str, new: str, note: str) -> None:
        nonlocal s
        if new != s:
            steps.append({"op": op, "before": s, "after": new, "note": note})
            s = new

    step("trim", s.strip(), "removed leading/trailing whitespace")
    step("uppercase", s.upper(), "identifiers compared case-insensitively")
    step("unify_dashes", "".join("-" if ch in DASHES else ch for ch in s), "typographic dashes/underscores mapped to '-'")
    step("strip_edge_punctuation", s.strip(EDGE_JUNK), "removed punctuation at the string edges")
    if remove_spaces:
        step("remove_internal_spaces", re.sub(r"\s+", "", s), "internal whitespace removed")
    else:
        step("collapse_spaces", re.sub(r"\s+", " ", s), "internal whitespace collapsed")
    step("collapse_separators", re.sub(r"-{2,}", "-", s), "repeated separators collapsed")
    return s, steps


def confusable_key(s: str) -> str:
    return "".join(_CANON.get(ch, ch) for ch in s)


def are_confusable(a: str, b: str) -> bool:
    return a != b and _CANON.get(a, a) == _CANON.get(b, b)
