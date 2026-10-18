"""Mapping of free-text component types to the detector's canonical classes."""
from __future__ import annotations

import re

TYPE_KEYWORDS: list[tuple[str, list[str]]] = [
    ("earth_bar", ["earth bar", "pe bar", "ground bar", "earthing bar", "pe busbar", "earth terminal bar"]),
    ("terminal_block", ["terminal block", "terminal strip", "terminals", "terminal", "reihenklemme", "klemme"]),
    ("power_supply", ["power supply", "psu", "smps", "dc supply", "24v supply", "netzteil"]),
    ("contactor", ["contactor", "schütz", "schuetz", "motor starter contactor"]),
    ("relay", ["relay", "interface relay", "safety relay", "relais"]),
    ("circuit_breaker", ["circuit breaker", "breaker", "mcb", "mccb", "rcbo", "miniature circuit", "main switch", "isolator"]),
]

# IEC 81346-style tag prefixes; used only when no component type is given (documented heuristic)
TAG_PREFIX: list[tuple[str, str]] = [
    ("QF", "circuit_breaker"), ("CB", "circuit_breaker"), ("MCB", "circuit_breaker"), ("FC", "circuit_breaker"), ("F", "circuit_breaker"),
    ("KM", "contactor"), ("KA", "relay"), ("K", "contactor"),
    ("PS", "power_supply"), ("G", "power_supply"), ("TC", "power_supply"),
    ("PE", "earth_bar"), ("X", "terminal_block"),
]

SUPPORTED_CLASSES = ["circuit_breaker", "contactor", "power_supply", "terminal_block", "earth_bar", "relay"]


def canonical_class(component_type: str | None, tag: str | None = None) -> tuple[str | None, str]:
    """Return (class, source) where source is 'type', 'tag_prefix' or 'unknown'."""
    if component_type:
        t = component_type.strip().lower()
        for cls, kws in TYPE_KEYWORDS:
            if any(k in t for k in kws):
                return cls, "type"
    if tag:
        m = re.match(r"^[-=+]?([A-Z]+)", tag.strip().upper())
        if m:
            prefix = m.group(1)
            for p, cls in TAG_PREFIX:
                if prefix == p or (len(p) >= 2 and prefix.startswith(p)):
                    return cls, "tag_prefix"
    return None, "unknown"
