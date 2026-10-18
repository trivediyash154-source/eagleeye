import numpy as np

from app.drawing.pdf_parser import extract_zones, inspect_pdf, locate_identifier, parse_drawing
from app.inspection.verify import ExpComp, ExpIdent, ObsDet, ObsText, Verifier, VerifyContext


def test_parse_demo_ga(demo_dir):
    data = (demo_dir / "CAB-07_GA_drawing_SYNTHETIC.pdf").read_bytes()
    info = inspect_pdf(data)
    assert info["page_count"] == 1 and info["pages"][0]["kind"] == "vector"
    pd = parse_drawing(data, 0)
    zones = {z["code"]: z for z in extract_zones(pd)}
    assert set(zones) == {"Z1", "Z2", "Z3", "Z4", "Z5"}
    assert zones["Z1"]["name"] == "PROTECTION"
    loc = locate_identifier(pd, "PS12")
    assert loc["found"] and loc["match"] == "label_plate+body"
    assert locate_identifier(pd, "X12-4B")["found"]
    assert not locate_identifier(pd, "NOPE99")["found"]


def _ctx(H, supported=frozenset({"circuit_breaker"}), quality="good", checks=("component_presence", "device_label", "ferrule_label")):
    reg = {"status": "aligned" if H is not None else "failed", "usable": H is not None, "metrics": {}, "reasons": ["test"]}
    return VerifyContext(H=H, registration=reg, image=np.zeros((1000, 1000, 3), np.uint8), quality_rating=quality, supported_classes=set(supported),
                         detector_kind="custom", detector_available=True, detector_conf=0.35, ocr_available=True, zones_pt={}, checks=set(checks))


def test_missing_component_fails_only_with_registration():
    comp = ExpComp("c1", "CB44", "Z1", "circuit_breaker", "type", None, 1, [100, 100, 150, 200], None, "label_plate+body")
    fs = Verifier(_ctx(np.eye(3)), [], []).run([comp], [])
    assert fs[0]["verdict"] == "FAIL" and fs[0]["rule"] == "missing_at_expected_position"
    fs2 = Verifier(_ctx(None), [], []).run([comp], [])
    assert fs2[0]["verdict"] == "UNCERTAIN"


def test_presence_pass_weak_and_unsupported():
    comp = ExpComp("c1", "CB41", "Z1", "circuit_breaker", "type", None, 1, [100, 100, 150, 200], None, "x")
    strong = [ObsDet("d1", "circuit_breaker", 0.9, (102, 98, 151, 203), True)]
    assert Verifier(_ctx(np.eye(3)), strong, []).run([comp], [])[0]["verdict"] == "PASS"
    weak = [ObsDet("d1", "circuit_breaker", 0.1, (102, 98, 151, 203), False)]
    assert Verifier(_ctx(np.eye(3)), weak, []).run([comp], [])[0]["rule"] == "weak_detection"
    psu = ExpComp("c2", "PS11", "Z2", "power_supply", "type", None, 1, [300, 100, 350, 200], None, "x")
    f = Verifier(_ctx(np.eye(3)), [], []).run([psu], [])[0]
    assert f["verdict"] == "UNCERTAIN" and f["rule"] == "unsupported_class"


def test_ferrule_rules_with_registration():
    ident = ExpIdent("i1", "ferrule", "X12-4B", "X12:4", None, None, "Z4", [500, 500, 540, 512], None, "marker+terminal")
    wrong = [ObsText("o1", "X12-8B", "X12-8B", 0.97, (501, 500, 539, 512))]
    f = Verifier(_ctx(np.eye(3)), [], wrong).run([], [ident])[0]
    assert f["verdict"] == "FAIL" and f["observed_value"] == "X12-8B" and f["ocr_observation_id"] == "o1"
    f2 = Verifier(_ctx(None), [], wrong).run([], [ident])[0]
    assert f2["verdict"] == "UNCERTAIN" and f2["rule"] == "registration_unavailable"
