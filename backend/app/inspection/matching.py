"""Identifier comparison and verdict rules for device labels and ferrules.

Two policies are available per identifier type:

``confusion_aware`` (default)
    exact normalised match with adequate OCR confidence ........ PASS
    all differences are OCR-confusable substitutions (8/B, 0/O) . UNCERTAIN (possible misread)
    any non-confusable edit, reliable OCR, reliable association . FAIL
    anything else ............................................... UNCERTAIN

``distance_bands`` (the original slide-deck rule)
    d = 0 → PASS,  d ≤ uncertain_max_distance → UNCERTAIN,  otherwise FAIL
    (still gated by OCR confidence and association reliability)

A one-character difference can be decisive for an electrical identifier (X12-4B vs X12-8B are
different terminals), which is why the default policy does not treat every d=1 as UNCERTAIN.
No observation, or an unreliable one, never yields FAIL.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from rapidfuzz.distance import Levenshtein

from ..ocr.normalize import are_confusable, confusable_key, normalize

DEFAULT_POLICY = {
    "mode": "confusion_aware",
    "min_ocr_conf_pass": 0.45,
    "min_ocr_conf_fail": 0.55,
    "uncertain_max_distance": 1,
}


@dataclass
class Comparison:
    expected: str
    observed: str
    distance: int
    similarity: float
    edits: list[dict] = field(default_factory=list)
    confusable_only: bool = False

    def to_json(self) -> dict:
        return {
            "expected": self.expected, "observed": self.observed, "levenshtein_distance": self.distance,
            "normalized_similarity": round(self.similarity, 4), "edits": self.edits, "confusable_only": self.confusable_only,
        }


def compare(expected: str, observed: str) -> Comparison:
    e, _ = normalize(expected)
    o, _ = normalize(observed)
    d = int(Levenshtein.distance(e, o))
    sim = float(Levenshtein.normalized_similarity(e, o))
    edits = []
    confusable_only = d > 0
    for op in Levenshtein.editops(e, o):
        tag, sp, dp = op.tag, op.src_pos, op.dest_pos
        ec = e[sp] if sp < len(e) else ""
        oc = o[dp] if dp < len(o) else ""
        if tag == "replace":
            c = are_confusable(ec, oc)
            edits.append({"op": "substitute", "position": sp, "expected": ec, "observed": oc, "confusable": c})
            confusable_only = confusable_only and c
        elif tag == "delete":
            edits.append({"op": "missing", "position": sp, "expected": ec})
            confusable_only = False
        else:
            edits.append({"op": "extra", "position": dp, "observed": oc})
            confusable_only = False
    if confusable_only and confusable_key(e) != confusable_key(o):
        confusable_only = False
    return Comparison(e, o, d, sim, edits, confusable_only)


@dataclass
class Decision:
    verdict: str
    rule: str
    explanation: str
    reasons: list[str]
    comparison: Comparison | None = None


def decide_identifier(kind: str, expected: str, observed: str | None, ocr_conf: float | None, association_reliable: bool,
                      association_note: str, policy: dict | None = None) -> Decision:
    p = {**DEFAULT_POLICY, **(policy or {})}
    noun = "ferrule" if kind == "ferrule" else "device label"
    if observed is None or observed == "":
        return Decision("UNCERTAIN", "no_readable_text", f"No readable text could be associated with the expected {noun} '{expected}'. {association_note} An unreadable label is not treated as a mismatch.".strip(), ["no_readable_text"])
    cmp_ = compare(expected, observed)
    conf = ocr_conf if ocr_conf is not None else 0.0
    if cmp_.distance == 0:
        if conf >= p["min_ocr_conf_pass"] and association_reliable:
            return Decision("PASS", "exact_match", f"Observed '{cmp_.observed}' matches expected '{cmp_.expected}' exactly (OCR confidence {conf:.2f} ≥ {p['min_ocr_conf_pass']}). {association_note}".strip(), [], cmp_)
        if not association_reliable:
            return Decision("UNCERTAIN", "match_unverified_position", f"Text '{cmp_.observed}' matches the expected {noun}, but it could not be reliably tied to the expected position. {association_note}".strip(), ["ambiguous_association"], cmp_)
        return Decision("UNCERTAIN", "low_ocr_confidence", f"Observed text matches '{cmp_.expected}' but OCR confidence {conf:.2f} is below {p['min_ocr_conf_pass']}.", ["low_ocr_confidence"], cmp_)
    diff_txt = ", ".join(
        f"'{e['expected']}'→'{e['observed']}'" + (" (confusable)" if e.get("confusable") else "") if e["op"] == "substitute" else (f"missing '{e['expected']}'" if e["op"] == "missing" else f"extra '{e['observed']}'")
        for e in cmp_.edits
    )
    if len(cmp_.observed) < len(cmp_.expected) and any(e["op"] == "missing" for e in cmp_.edits):
        return Decision("UNCERTAIN", "possible_partial_read", f"Observed '{cmp_.observed}' is shorter than expected '{cmp_.expected}' ({diff_txt}); the {noun} may be partly occluded or cut off, so a mismatch cannot be confirmed.", ["possible_partial_read"], cmp_)
    if p["mode"] == "distance_bands":
        if cmp_.distance <= p["uncertain_max_distance"]:
            return Decision("UNCERTAIN", "near_match_distance_band", f"Observed '{cmp_.observed}' differs from expected '{cmp_.expected}' by d={cmp_.distance} ({diff_txt}); within the near-match band (d ≤ {p['uncertain_max_distance']}).", ["near_match"], cmp_)
    elif cmp_.confusable_only:
        return Decision("UNCERTAIN", "confusable_characters", f"Observed '{cmp_.observed}' differs from expected '{cmp_.expected}' only by visually confusable characters ({diff_txt}). This may be an OCR misread or a misprinted {noun}; human review required.", ["confusable_characters"], cmp_)
    if conf < p["min_ocr_conf_fail"]:
        return Decision("UNCERTAIN", "mismatch_low_confidence", f"Observed '{cmp_.observed}' differs from expected '{cmp_.expected}' (d={cmp_.distance}: {diff_txt}) but OCR confidence {conf:.2f} is below the {p['min_ocr_conf_fail']} required to confirm a mismatch.", ["low_ocr_confidence"], cmp_)
    if not association_reliable:
        return Decision("UNCERTAIN", "mismatch_unverified_position", f"A differing text '{cmp_.observed}' was read near the expected position, but the association is not reliable enough to confirm a mismatch. {association_note}".strip(), ["ambiguous_association"], cmp_)
    return Decision("FAIL", "identifier_mismatch", f"Expected {noun} '{cmp_.expected}' but read '{cmp_.observed}' (Levenshtein d={cmp_.distance}: {diff_txt}) with OCR confidence {conf:.2f}. {association_note}".strip(), [], cmp_)
