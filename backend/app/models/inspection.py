from __future__ import annotations

from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.db import Base
from ..core.util import new_id, utcnow


class Inspection(Base):
    """An inspection case for one cabinet. Holds an immutable sequence of versions."""

    __tablename__ = "inspections"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("insp"))
    code: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    title: Mapped[str] = mapped_column(String(200))
    cabinet_id: Mapped[str] = mapped_column(String(120), index=True)
    site: Mapped[str | None] = mapped_column(String(200))
    reference: Mapped[str | None] = mapped_column(String(120))
    inspector: Mapped[str | None] = mapped_column(String(120))
    project_ref: Mapped[str | None] = mapped_column(String(120))
    notes: Mapped[str | None] = mapped_column(Text)
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    versions: Mapped[list[InspectionVersion]] = relationship(back_populates="inspection", order_by="InspectionVersion.version_no", cascade="all, delete-orphan")


class InspectionVersion(Base):
    """One execution of the pipeline. Never overwritten: reinspection creates a new version."""

    __tablename__ = "inspection_versions"
    __table_args__ = (UniqueConstraint("inspection_id", "version_no", name="uq_version_no"),)

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("ver"))
    inspection_id: Mapped[str] = mapped_column(ForeignKey("inspections.id", ondelete="CASCADE"), index=True)
    version_no: Mapped[int] = mapped_column(Integer)
    label: Mapped[str] = mapped_column(String(120), default="Initial inspection")
    parent_version_id: Mapped[str | None] = mapped_column(ForeignKey("inspection_versions.id"), nullable=True)
    status: Mapped[str] = mapped_column(String(24), default="draft", index=True)  # draft|queued|running|completed|failed|cancelled
    config: Mapped[dict] = mapped_column(JSON, default=dict)
    summary: Mapped[dict] = mapped_column(JSON, default=dict)
    registration: Mapped[dict] = mapped_column(JSON, default=dict)
    preprocessing: Mapped[dict] = mapped_column(JSON, default=dict)
    detector_config_id: Mapped[str | None] = mapped_column(ForeignKey("model_configurations.id"), nullable=True)
    ocr_config_id: Mapped[str | None] = mapped_column(ForeignKey("model_configurations.id"), nullable=True)
    error: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    duration_ms: Mapped[int | None] = mapped_column(Integer)

    inspection: Mapped[Inspection] = relationship(back_populates="versions")
    assets: Mapped[list[InputAsset]] = relationship(back_populates="version", cascade="all, delete-orphan")


class InputAsset(Base):
    """An uploaded input file. Bytes live in file storage; the row stores metadata + hash."""

    __tablename__ = "input_assets"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("asset"))
    inspection_id: Mapped[str] = mapped_column(ForeignKey("inspections.id", ondelete="CASCADE"), index=True)
    version_id: Mapped[str] = mapped_column(ForeignKey("inspection_versions.id", ondelete="CASCADE"), index=True)
    kind: Mapped[str] = mapped_column(String(24), index=True)  # photo | drawing | expected_list
    original_filename: Mapped[str] = mapped_column(String(255))
    storage_key: Mapped[str] = mapped_column(String(255))
    content_type: Mapped[str] = mapped_column(String(100))
    size_bytes: Mapped[int] = mapped_column(Integer)
    sha256: Mapped[str] = mapped_column(String(64), index=True)
    analysis: Mapped[dict] = mapped_column(JSON, default=dict)
    inherited_from_asset_id: Mapped[str | None] = mapped_column(String(40))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    version: Mapped[InspectionVersion] = relationship(back_populates="assets")


class ModelConfiguration(Base):
    """A detector/OCR configuration snapshot used by one or more inspection runs."""

    __tablename__ = "model_configurations"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("mcfg"))
    kind: Mapped[str] = mapped_column(String(24))  # detector | ocr
    name: Mapped[str] = mapped_column(String(200))
    fingerprint: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    params: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
