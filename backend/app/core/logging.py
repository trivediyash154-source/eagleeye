"""Structured operational logging with an in-memory ring buffer for the diagnostics screen.

Log records never include image contents, file bytes, credentials or environment secrets.
Values whose keys look sensitive are redacted before they reach the buffer.
"""
from __future__ import annotations

import logging
import re
import threading
from collections import deque
from datetime import datetime, timezone
from typing import Any

_SENSITIVE = re.compile(r"(pass(word)?|secret|token|api[_-]?key|authorization|cookie|credential|dsn|database_url)", re.I)
_URL_CRED = re.compile(r"(\w+://)([^:/@\s]+):([^@\s]+)@")


def redact(value: Any, key: str | None = None) -> Any:
    if key and _SENSITIVE.search(key):
        return "***redacted***"
    if isinstance(value, str):
        return _URL_CRED.sub(r"\1\2:***@", value)
    if isinstance(value, dict):
        return {k: redact(v, k) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [redact(v) for v in value]
    return value


class RingBufferHandler(logging.Handler):
    def __init__(self, capacity: int = 1000):
        super().__init__()
        self.buffer: deque[dict] = deque(maxlen=capacity)
        self._buf_lock = threading.Lock()
        self._seq = 0

    def emit(self, record: logging.LogRecord) -> None:
        try:
            ctx = getattr(record, "ctx", None) or {}
            entry = {
                "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
                "level": record.levelname,
                "component": record.name.replace("eagleeye.", ""),
                "message": redact(record.getMessage()),
                "context": redact(ctx) if isinstance(ctx, dict) else {},
            }
            with self._buf_lock:
                self._seq += 1
                entry["seq"] = self._seq
                self.buffer.append(entry)
        except Exception:  # pragma: no cover - logging must never raise
            pass

    def entries(self, level: str | None = None, component: str | None = None, limit: int = 200) -> list[dict]:
        with self._buf_lock:
            items = list(self.buffer)
        if level:
            order = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
            min_i = order.index(level.upper()) if level.upper() in order else 0
            items = [e for e in items if order.index(e["level"]) >= min_i]
        if component:
            items = [e for e in items if e["component"].startswith(component)]
        return list(reversed(items[-limit:]))


ring_handler = RingBufferHandler()
_configured = False


def configure_logging(level: int = logging.INFO) -> None:
    global _configured
    if _configured:
        return
    root = logging.getLogger("eagleeye")
    root.setLevel(level)
    fmt = logging.Formatter("%(asctime)s %(levelname)s [%(name)s] %(message)s")
    sh = logging.StreamHandler()
    sh.setFormatter(fmt)
    root.addHandler(sh)
    root.addHandler(ring_handler)
    root.propagate = False
    _configured = True


def get_logger(name: str) -> logging.Logger:
    configure_logging()
    return logging.getLogger(f"eagleeye.{name}")


def log_event(logger: logging.Logger, level: int, message: str, **ctx: Any) -> None:
    logger.log(level, message, extra={"ctx": ctx})
