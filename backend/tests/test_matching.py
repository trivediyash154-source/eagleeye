from app.inspection.matching import compare, decide_identifier
from app.ocr.normalize import confusable_key, normalize


def test_normalize_records_steps_and_keeps_confusables():
    norm, steps = normalize("  x12–4b ")
    assert norm == "X12-4B"
    assert [s["op"] for s in steps] == ["trim", "uppercase", "unify_dashes"]
    # O/0 are never rewritten in the normalised value
    assert normalize("QFO1")[0] == "QFO1"
    assert confusable_key("QFO1") == confusable_key("QF01")


def test_exact_match_passes():
    d = decide_identifier("ferrule", "X12-4B", "X12-4B", 0.95, True, "")
    assert d.verdict == "PASS" and d.rule == "exact_match"


def test_non_confusable_substitution_fails():
    # the deck example X12-4B vs X12-8B is Levenshtein 1, but 4/8 are not OCR-confusable
    d = decide_identifier("ferrule", "X12-4B", "X12-8B", 0.95, True, "")
    assert d.verdict == "FAIL"
    assert d.comparison.distance == 1


def test_confusable_substitution_is_uncertain():
    d = decide_identifier("ferrule", "X12-6B", "X12-68", 0.95, True, "")
    assert d.verdict == "UNCERTAIN" and d.rule == "confusable_characters"
    assert d.comparison.confusable_only


def test_missing_text_never_fails():
    d = decide_identifier("device_label", "K2", None, None, True, "")
    assert d.verdict == "UNCERTAIN" and "no_readable_text" in d.reasons


def test_low_confidence_mismatch_is_uncertain():
    d = decide_identifier("ferrule", "X12-4B", "X12-8B", 0.3, True, "")
    assert d.verdict == "UNCERTAIN" and d.rule == "mismatch_low_confidence"


def test_partial_read_is_uncertain():
    d = decide_identifier("device_label", "K2", "2", 0.9, True, "")
    assert d.verdict == "UNCERTAIN" and d.rule == "possible_partial_read"


def test_unreliable_association_blocks_fail_and_pass():
    assert decide_identifier("ferrule", "X12-4B", "X12-9C", 0.95, False, "").verdict == "UNCERTAIN"
    assert decide_identifier("ferrule", "X12-4B", "X12-4B", 0.95, False, "").verdict == "UNCERTAIN"


def test_distance_band_policy():
    d = decide_identifier("ferrule", "X12-4B", "X12-8B", 0.95, True, "", {"mode": "distance_bands"})
    assert d.verdict == "UNCERTAIN"
    d2 = decide_identifier("ferrule", "X12-4B", "X12-3A", 0.95, True, "", {"mode": "distance_bands"})
    assert d2.verdict == "FAIL"


def test_compare_edit_ops():
    c = compare("PS12", "PS21")
    assert c.distance == 2
    assert not c.confusable_only


def test_unstable_reading_blocks_fail():
    # one variant read X1Z-JA, the other three readings disagree with it
    d = decide_identifier("ferrule", "X12-1A", "X1Z-JA", 0.79, True, "", support=(1, 4))
    assert d.verdict == "UNCERTAIN" and d.rule == "unstable_reading"
    d2 = decide_identifier("ferrule", "X12-4B", "X12-8B", 0.99, True, "", support=(3, 4))
    assert d2.verdict == "FAIL"
