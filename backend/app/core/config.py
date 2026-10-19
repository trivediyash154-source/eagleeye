"""Application settings.

All settings can be overridden with environment variables prefixed ``EAGLEEYE_``
(see ``.env.example`` at the repository root). Secrets are never hard-coded here.
"""
from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[2]
REPO_ROOT = BACKEND_DIR.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="EAGLEEYE_", env_file=(REPO_ROOT / ".env", BACKEND_DIR / ".env"), extra="ignore")

    app_name: str = "EAGLE EYE"
    api_version: str = "v1"
    environment: str = "development"

    # Storage / database
    data_dir: Path = BACKEND_DIR / "var"
    database_url: str | None = None  # defaults to SQLite inside data_dir
    auto_migrate: bool = True

    # HTTP
    cors_origins: list[str] = Field(
        default_factory=lambda: [
            "http://localhost:8080",
            "http://127.0.0.1:8080",
            "http://localhost:5000",
            "http://127.0.0.1:5000",
        ]
    )
    # Web console served at "/". Empty value disables. Default: a local Flutter build if present,
    # otherwise the prebuilt bundle committed in frontend/prebuilt/web (no Flutter SDK needed).
    frontend_dist: Path | None = None

    # Upload limits (megabytes)
    max_image_mb: int = 25
    max_pdf_mb: int = 50
    max_sheet_mb: int = 10
    max_image_pixels: int = 80_000_000

    # Detector
    detector_weights: Path = REPO_ROOT / "models" / "eagleeye-synth-v1.pt"
    detector_fallback_weights: Path = REPO_ROOT / "models" / "cache" / "yolov8n.pt"
    detector_device: str = "auto"  # auto | cpu | cuda:0 | mps
    detector_conf: float = 0.35
    detector_iou: float = 0.5
    detector_min_store_conf: float = 0.05
    detector_imgsz: int = 640
    detector_tile_size: int = 1024
    detector_tile_overlap: float = 0.2
    detector_tiling: bool = True

    # OCR
    ocr_engine: str = "auto"  # auto | paddle | easyocr | none
    ocr_languages: list[str] = Field(default_factory=lambda: ["en"])
    ocr_gpu: bool = False
    easyocr_model_dir: Path = REPO_ROOT / "models" / "cache" / "easyocr"
    ocr_allow_download: bool = False
    # IEC 81346 reference designations avoid the letters I and O because they are confused with 1 and 0.
    ocr_exclude_io: bool = True
    ocr_full_image_canvas: int = 2560
    ocr_crop_upscale: float = 2.5

    # Processing
    max_processing_side: int = 4000
    job_workers: int = 1

    # Review identity (no authentication in this prototype)
    reviewer_identity: str = "local-demo-reviewer"

    # Demo fixtures
    demo_dir: Path = REPO_ROOT / "data" / "demo"

    # Retention (documented policy; enforced by `python -m app.maintenance purge`)
    temp_retention_hours: int = 24

    @property
    def resolved_database_url(self) -> str:
        if self.database_url:
            return self.database_url
        return f"sqlite:///{(self.data_dir / 'eagleeye.db').as_posix()}"

    @property
    def resolved_frontend_dist(self) -> Path | None:
        if self.frontend_dist is not None:
            p = Path(self.frontend_dist)
            return p if str(p) not in ("", ".") and (p / "index.html").is_file() else None
        for p in (REPO_ROOT / "frontend" / "build" / "web", REPO_ROOT / "frontend" / "prebuilt" / "web"):
            if (p / "index.html").is_file():
                return p
        return None

    @property
    def storage_dir(self) -> Path:
        return self.data_dir / "storage"

    @property
    def is_sqlite(self) -> bool:
        return self.resolved_database_url.startswith("sqlite")


@lru_cache
def get_settings() -> Settings:
    s = Settings()
    s.data_dir.mkdir(parents=True, exist_ok=True)
    s.storage_dir.mkdir(parents=True, exist_ok=True)
    return s
