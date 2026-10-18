from __future__ import annotations

from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from ..core.db import Base
from ..core.util import new_id, utcnow


class Detection(Base):
    """A detector output. Box coordinates are ORIGINAL image pixels (after EXIF orientation)."""

    __tablename__ = "detections"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("det"))
    version_id: Mapped[str] = mapped_column(ForeignKey("inspection_versions.id", ondelete="CASCADE"), index=True)
    class_id: Mapped[int] = mapped_column(Integer)
    class_name: Mapped[str] = mapped_column(String(80), index=True)
    confidence: Mapped[float] = mapped_column(Float)
    above_threshold: Mapped[bool] = mapped_column(Boolean, default=True)
    x0: Mapped[float] = mapped_column(Float)
    y0: Mapped[float] = mapped_column(Float)
    x1: Mapped[float] = mapped_column(Float)
    y1: Mapped[float] = mapped_column(Float)
    source: Mapped[str] = mapped_column(String(24))  # full | tile
    model_name: Mapped[str] = mapped_column(String(120))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class OcrObservation(Base):
    """A recognised text region. The raw OCR string is preserved alongside its normalised form."""

    __tablename__ = "ocr_observations"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("ocr"))
    version_id: Mapped[str] = mapped_column(ForeignKey("inspection_versions.id", ondelete="CASCADE"), index=True)
    raw_text: Mapped[str] = mapped_column(String(255))
    normalized_text: Mapped[str] = mapped_column(String(255), index=True)
    normalization_steps: Mapped[list] = mapped_column(JSON, default=list)
    confidence: Mapped[float] = mapped_column(Float)
    polygon: Mapped[list] = mapped_column(JSON, default=list)
    x0: Mapped[float] = mapped_column(Float)
    y0: Mapped[float] = mapped_column(Float)
    x1: Mapped[float] = mapped_column(Float)
    y1: Mapped[float] = mapped_column(Float)
    region: Mapped[str] = mapped_column(String(24))  # full | crop
    variant: Mapped[str] = mapped_column(String(40))
    alternatives: Mapped[list] = mapped_column(JSON, default=list)
    engine: Mapped[str] = mapped_column(String(60))
    detection_id: Mapped[str | None] = mapped_column(ForeignKey("detections.id", ondelete="SET NULL"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
