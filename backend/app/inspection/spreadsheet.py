"""Expected component / wire list ingestion (XLSX, XLS, CSV).

No fixed schema is assumed: the header row is detected per sheet, columns are mapped to
known fields through a synonym table (editable by the inspector), and every row keeps a
reference to its source sheet and row number.
"""
from __future__ import annotations

import csv
import io
import re
from dataclasses import dataclass

import pandas as pd
from rapidfuzz import fuzz

FIELDS: dict[str, dict] = {
    "zone": {"label": "Zone", "synonyms": ["zone", "zone id", "zone code", "area", "section", "panel zone", "location"]},
    "component_id": {"label": "Component ID / reference designation", "synonyms": ["component id", "component", "ref", "ref designation", "reference designation", "reference", "designation", "device", "device tag", "tag", "bmk", "item tag", "equipment", "ref des", "refdes"]},
    "component_type": {"label": "Component type", "synonyms": ["component type", "type", "device type", "category", "part type", "description", "item"]},
    "expected_label": {"label": "Expected device label", "synonyms": ["device label", "label", "expected label", "label text", "nameplate", "marking"]},
    "ferrule": {"label": "Expected ferrule", "synonyms": ["ferrule", "ferrule no", "ferrule number", "expected ferrule", "wire marker", "marker", "wire no", "wire number", "wire id", "cable marker"]},
    "terminal": {"label": "Terminal reference", "synonyms": ["terminal", "terminal ref", "terminal no", "terminal number", "term", "terminal point", "to terminal", "to"]},
    "wire_color": {"label": "Expected wire colour", "synonyms": ["wire colour", "wire color", "colour", "color", "core colour", "core color"]},
    "quantity": {"label": "Expected quantity", "synonyms": ["qty", "quantity", "count", "expected quantity", "no of"]},
    "from_device": {"label": "From device", "synonyms": ["from device", "from", "source", "source device", "origin"]},
    "notes": {"label": "Notes", "synonyms": ["notes", "remarks", "remark", "comment", "comments"]},
}

MAX_ROWS = 5000


class SheetError(ValueError):
    pass


def _clean_header(h) -> str:
    s = str(h).strip().lower()
    s = re.sub(r"[._/\\#()\[\]]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def _cell(v) -> str | None:
    if v is None:
        return None
    if isinstance(v, float):
        if pd.isna(v):
            return None
        if v.is_integer():
            return str(int(v))
    s = str(v).strip()
    return s or None


def read_workbook(data: bytes, filename: str) -> dict[str, pd.DataFrame]:
    name = filename.lower()
    try:
        if name.endswith(".csv"):
            text = None
            for enc in ("utf-8-sig", "utf-8", "cp1252", "latin-1"):
                try:
                    text = data.decode(enc)
                    break
                except UnicodeDecodeError:
                    continue
            if text is None:
                raise SheetError("CSV encoding not recognised")
            try:
                dialect = csv.Sniffer().sniff(text[:4096], delimiters=",;\t|")
                sep = dialect.delimiter
            except csv.Error:
                sep = ","
            df = pd.read_csv(io.StringIO(text), sep=sep, header=None, dtype=object, keep_default_na=False, nrows=MAX_ROWS)
            return {"CSV": df}
        engine = "openpyxl" if name.endswith((".xlsx", ".xlsm")) else ("xlrd" if name.endswith(".xls") else None)
        if engine is None:
            raise SheetError("unsupported spreadsheet type; use .xlsx, .xls or .csv")
        sheets = pd.read_excel(io.BytesIO(data), sheet_name=None, header=None, dtype=object, engine=engine, nrows=MAX_ROWS)
        return {str(k): v for k, v in sheets.items()}
    except SheetError:
        raise
    except Exception as exc:
        raise SheetError(f"spreadsheet could not be read: {type(exc).__name__}: {exc}") from exc


def suggest_field(header: str) -> tuple[str | None, int]:
    h = _clean_header(header)
    if not h:
        return None, 0
    for field_name, spec in FIELDS.items():
        if h in spec["synonyms"]:
            return field_name, 100
    best, score = None, 0
    for field_name, spec in FIELDS.items():
        for syn in spec["synonyms"]:
            sc = fuzz.token_sort_ratio(h, syn)
            if len(syn) > 3 and (h.startswith(syn) or syn in h.split()):
                sc = max(sc, 88)
            if sc > score:
                best, score = field_name, sc
    return (best, score) if score >= 82 else (None, score)


def detect_header_row(df: pd.DataFrame, max_scan: int = 15) -> int:
    best_row, best_score = 0, -1
    for i in range(min(max_scan, len(df))):
        row = [_cell(v) for v in df.iloc[i].tolist()]
        nonempty = [c for c in row if c]
        if len(nonempty) < 2:
            continue
        hits = sum(1 for c in nonempty if suggest_field(c)[0])
        score = hits * 10 + len(nonempty) * 0.1
        if score > best_score:
            best_row, best_score = i, score
    return best_row


@dataclass
class SheetAnalysis:
    name: str
    header_row: int
    columns: list[str]
    mapping: dict[str, str | None]  # column header -> field
    mapping_scores: dict[str, int]
    preview: list[dict]
    row_count: int
    role: str  # components | wires | unknown

    def to_json(self) -> dict:
        return {
            "name": self.name, "header_row": self.header_row, "columns": self.columns, "mapping": self.mapping,
            "mapping_scores": self.mapping_scores, "preview": self.preview, "row_count": self.row_count, "role": self.role,
        }


def _role(mapping: dict[str, str | None]) -> str:
    fields = set(v for v in mapping.values() if v)
    if fields & {"ferrule", "terminal"}:
        return "wires"
    if "component_id" in fields:
        return "components"
    return "unknown"


def analyze_sheet(name: str, df: pd.DataFrame, header_row: int | None = None, mapping: dict[str, str | None] | None = None) -> SheetAnalysis:
    df = df.dropna(how="all")
    if df.empty:
        return SheetAnalysis(name, 0, [], {}, {}, [], 0, "unknown")
    df = df.reset_index(drop=True)
    hr = detect_header_row(df) if header_row is None else max(0, min(header_row, len(df) - 1))
    headers_raw = [_cell(v) or f"Column {i + 1}" for i, v in enumerate(df.iloc[hr].tolist())]
    seen: dict[str, int] = {}
    headers = []
    for h in headers_raw:
        if h in seen:
            seen[h] += 1
            h = f"{h} ({seen[h]})"
        else:
            seen[h] = 1
        headers.append(h)
    auto: dict[str, str | None] = {}
    scores: dict[str, int] = {}
    used: set[str] = set()
    for h in headers:
        f, sc = suggest_field(h)
        scores[h] = int(sc)
        if f and f not in used:
            auto[h] = f
            used.add(f)
        else:
            auto[h] = None
    if mapping:
        auto = {h: (mapping.get(h) if mapping.get(h) in FIELDS else None) for h in headers}
    body = df.iloc[hr + 1:]
    preview = []
    for idx, row in body.head(25).iterrows():
        preview.append({"row": int(idx) + 1, "values": {h: _cell(v) for h, v in zip(headers, row.tolist())}})
    return SheetAnalysis(name, hr, headers, auto, scores, preview, int(len(body)), _role(auto))


def analyze_workbook(data: bytes, filename: str) -> dict:
    sheets = read_workbook(data, filename)
    out = []
    for name, df in sheets.items():
        out.append(analyze_sheet(name, df).to_json())
    return {"sheets": out, "fields": {k: v["label"] for k, v in FIELDS.items()}}


def parse_records(data: bytes, filename: str, sheet_configs: list[dict] | None = None) -> dict:
    """Parse rows into expected components and expected identifiers.

    sheet_configs: [{"name", "include", "header_row", "mapping"}]; default = auto-detect all sheets.
    """
    sheets = read_workbook(data, filename)
    cfg_by_name = {c["name"]: c for c in (sheet_configs or [])}
    components: list[dict] = []
    identifiers: list[dict] = []
    warnings: list[dict] = []
    used_sheets = []
    for name, df in sheets.items():
        cfg = cfg_by_name.get(name, {})
        if cfg and not cfg.get("include", True):
            continue
        an = analyze_sheet(name, df, cfg.get("header_row"), cfg.get("mapping"))
        if an.role == "unknown":
            if cfg.get("include"):
                warnings.append({"sheet": name, "code": "unmapped_sheet", "message": f"Sheet '{name}' has no Component ID, Ferrule or Terminal column mapped; it was ignored."})
            continue
        used_sheets.append({"name": name, "role": an.role, "header_row": an.header_row, "mapping": an.mapping})
        col_for = {f: h for h, f in an.mapping.items() if f}
        body = df.dropna(how="all").reset_index(drop=True).iloc[an.header_row + 1:]
        for idx, row in body.iterrows():
            vals = {h: _cell(v) for h, v in zip(an.columns, row.tolist())}
            rec = {f: vals.get(h) for f, h in col_for.items()}
            src_row = int(idx) + 1
            if not any(rec.values()):
                continue
            if an.role == "wires":
                if not rec.get("ferrule") and not rec.get("terminal"):
                    warnings.append({"sheet": name, "row": src_row, "code": "missing_expected_value", "message": "Wire row without ferrule or terminal value skipped."})
                    continue
                identifiers.append({
                    "kind": "ferrule" if rec.get("ferrule") else "terminal",
                    "value": rec.get("ferrule"),
                    "terminal_ref": rec.get("terminal"),
                    "wire_color": rec.get("wire_color"),
                    "component_tag": rec.get("from_device") or rec.get("component_id"),
                    "zone_code": (rec.get("zone") or "").upper() or None,
                    "source_sheet": name,
                    "source_row": src_row,
                })
            else:
                tag = rec.get("component_id")
                if not tag:
                    warnings.append({"sheet": name, "row": src_row, "code": "missing_component_id", "message": "Row without a component ID skipped."})
                    continue
                qty_raw = rec.get("quantity")
                try:
                    qty = int(float(qty_raw)) if qty_raw else 1
                except ValueError:
                    qty = 1
                    warnings.append({"sheet": name, "row": src_row, "code": "invalid_quantity", "message": f"Quantity '{qty_raw}' is not a number; assumed 1."})
                if not rec.get("component_type") and not rec.get("expected_label"):
                    warnings.append({"sheet": name, "row": src_row, "code": "missing_expected_value", "message": f"Component {tag} has neither a type nor an expected label."})
                components.append({
                    "tag": tag.strip(),
                    "component_type": rec.get("component_type"),
                    "expected_label": rec.get("expected_label"),
                    "zone_code": (rec.get("zone") or "").upper() or None,
                    "quantity": max(1, qty),
                    "notes": rec.get("notes"),
                    "source_sheet": name,
                    "source_row": src_row,
                })
    # duplicate checks
    seen: dict[str, dict] = {}
    for c in components:
        k = c["tag"].upper()
        if k in seen:
            warnings.append({"sheet": c["source_sheet"], "row": c["source_row"], "code": "duplicate_component", "message": f"Component ID {c['tag']} also appears in {seen[k]['source_sheet']} row {seen[k]['source_row']}."})
        else:
            seen[k] = c
    fseen: dict[str, dict] = {}
    for i in identifiers:
        if not i["value"]:
            continue
        k = i["value"].upper()
        if k in fseen:
            warnings.append({"sheet": i["source_sheet"], "row": i["source_row"], "code": "duplicate_ferrule", "message": f"Ferrule {i['value']} also appears in {fseen[k]['source_sheet']} row {fseen[k]['source_row']}."})
        else:
            fseen[k] = i
    return {"components": components, "identifiers": identifiers, "warnings": warnings, "sheets": used_sheets}
