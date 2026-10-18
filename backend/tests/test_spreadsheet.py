import io

from openpyxl import Workbook

from app.inspection.spreadsheet import analyze_workbook, parse_records, suggest_field
from app.inspection.taxonomy import canonical_class


def _xlsx() -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.title = "Parts"
    ws.append(["Cabinet 12 — component list"])
    ws.append([])
    ws.append(["Area", "Ref. Designation", "Device Type", "Label", "Qty"])
    ws.append(["Z1", "CB41", "MCB", "CB41", 1])
    ws.append(["Z1", "CB41", "MCB", "CB41", 1])
    ws.append(["Z2", "PS11", "Power supply", None, "two"])
    w2 = wb.create_sheet("Wires")
    w2.append(["Terminal", "Ferrule No.", "Wire Colour", "From"])
    w2.append(["X1:1", "X1-1A", "Brown", "CB41"])
    w2.append(["X1:2", "X1-1A", "Blue", "CB41"])
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def test_field_synonyms():
    assert suggest_field("Ref. Designation")[0] == "component_id"
    assert suggest_field("Ferrule No.")[0] == "ferrule"
    assert suggest_field("Wire Colour")[0] == "wire_color"
    assert suggest_field("Something unrelated")[0] is None


def test_header_detection_and_roles():
    an = analyze_workbook(_xlsx(), "list.xlsx")
    parts = next(s for s in an["sheets"] if s["name"] == "Parts")
    assert parts["header_row"] == 2
    assert parts["role"] == "components"
    wires = next(s for s in an["sheets"] if s["name"] == "Wires")
    assert wires["role"] == "wires"


def test_parse_records_with_warnings():
    res = parse_records(_xlsx(), "list.xlsx")
    assert len(res["components"]) == 3
    assert len(res["identifiers"]) == 2
    codes = {w["code"] for w in res["warnings"]}
    assert {"duplicate_component", "duplicate_ferrule", "invalid_quantity"} <= codes


def test_csv_semicolon():
    data = "Zone;Tag;Type\nZ1;K1;Contactor\n".encode()
    res = parse_records(data, "x.csv")
    assert res["components"][0]["tag"] == "K1"


def test_taxonomy():
    assert canonical_class("Miniature circuit breaker (MCB)")[0] == "circuit_breaker"
    assert canonical_class(None, "PS11") == ("power_supply", "tag_prefix")
    assert canonical_class("Terminal block")[0] == "terminal_block"
    assert canonical_class("Widget")[0] is None
