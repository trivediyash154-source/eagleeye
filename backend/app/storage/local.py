"""Local file storage with generated keys, SHA-256 integrity hashes and path-traversal protection.

Keys look like ``inspections/<inspection_id>/<version_id>/<category>/<uuid>.<ext>``. User-supplied
file names are never used to build paths; they are only stored as metadata.
"""
from __future__ import annotations

import hashlib
import re
import shutil
import uuid
from pathlib import Path

from ..core.config import get_settings

_SAFE_SEGMENT = re.compile(r"^[A-Za-z0-9_.-]{1,80}$")
_SAFE_EXT = re.compile(r"^[a-z0-9]{1,8}$")


class StorageError(Exception):
    pass


class LocalStorage:
    def __init__(self, root: Path | None = None):
        self.root = (root or get_settings().storage_dir).resolve()
        self.root.mkdir(parents=True, exist_ok=True)

    def _check_segment(self, seg: str) -> str:
        if not _SAFE_SEGMENT.match(seg) or seg in (".", ".."):
            raise StorageError(f"unsafe storage path segment: {seg!r}")
        return seg

    def make_key(self, *segments: str, ext: str) -> str:
        ext = ext.lower().lstrip(".")
        if not _SAFE_EXT.match(ext):
            raise StorageError("unsafe file extension")
        parts = [self._check_segment(s) for s in segments]
        return "/".join(parts + [f"{uuid.uuid4().hex}.{ext}"])

    def path_for(self, key: str) -> Path:
        if not key or key.startswith("/") or "\\" in key:
            raise StorageError("invalid storage key")
        for seg in key.split("/"):
            self._check_segment(seg)
        p = (self.root / key).resolve()
        if self.root not in p.parents:
            raise StorageError("storage key escapes storage root")
        return p

    def put_bytes(self, key: str, data: bytes) -> tuple[str, int]:
        p = self.path_for(key)
        p.parent.mkdir(parents=True, exist_ok=True)
        tmp = p.with_suffix(p.suffix + ".part")
        tmp.write_bytes(data)
        tmp.replace(p)
        return hashlib.sha256(data).hexdigest(), len(data)

    def put_file(self, key: str, src: Path) -> tuple[str, int]:
        p = self.path_for(key)
        p.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, p)
        return sha256_file(p), p.stat().st_size

    def read_bytes(self, key: str) -> bytes:
        return self.path_for(key).read_bytes()

    def exists(self, key: str | None) -> bool:
        if not key:
            return False
        try:
            return self.path_for(key).is_file()
        except StorageError:
            return False

    def writable(self) -> tuple[bool, str]:
        try:
            probe = self.root / f".probe-{uuid.uuid4().hex}"
            probe.write_bytes(b"ok")
            probe.unlink()
            return True, str(self.root)
        except Exception as exc:  # pragma: no cover - environment dependent
            return False, f"{type(exc).__name__}: {exc}"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


_storage: LocalStorage | None = None


def get_storage() -> LocalStorage:
    global _storage
    if _storage is None:
        _storage = LocalStorage()
    return _storage
