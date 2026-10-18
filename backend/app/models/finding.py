from __future__ import annotations

from datetime import datetime

from sqlalchemy import JSON, DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.db import Base
from ..core.util import new_id, utcnow


class Finding(Base):
    """Machine-generated verification result. Immutable after creation: reviews are separate rows."""

    __tablename__ = "findings"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("fnd"))
    inspection_id: Mapped[str] = mapped_column(ForeignKey("inspections.id", ondelete="CASCADE"), index=True)
    version_id: Mapped[str] = mapped_column(ForeignKey("inspection_versions.id", ondelete="CASCADE"), index=True)
    seq: Mapped[int] = mapped_column(Integer)
    finding_key: Mapped[str] = mapped_column(String(200), index=True)  # stable subject key across versions
    check_type: Mapped[str] = mapped_column(String(40), index=True)
    zone_code: Mapped[str | None] = mapped_column(String(40), index=True)
    subject: Mapped[str] = mapped_column(String(200))
    expected_value: Mapped[str | None] = mapped_column(String(255))
    observed_value: Mapped[str | None] = mapped_column(String(255))
    observed_raw: Mapped[str | None] = mapped_column(String(255))
    verdict: Mapped[str] = mapped_column(String(16), index=True)  # PASS | FAIL | UNCERTAIN
    rule: Mapped[str] = mapped_column(String(80))
    explanation: Mapped[str] = mapped_column(Text)
    confidences: Mapped[dict] = mapped_column(JSON, default=dict)
    review_reasons: Mapped[list] = mapped_column(JSON, default=list)
    bbox: Mapped[list | None] = mapped_column(JSON)  # original image pixels
    expected_bbox: Mapped[list | None] = mapped_column(JSON)  # projected expected region (image pixels)
    drawing_bbox: Mapped[list | None] = mapped_column(JSON)
    detection_id: Mapped[str | None] = mapped_column(ForeignKey("detections.id", ondelete="SET NULL"), nullable=True)
    ocr_observation_id: Mapped[str | None] = mapped_column(ForeignKey("ocr_observations.id", ondelete="SET NULL"), nullable=True)
    details: Mapped[dict] = mapped_column(JSON, default=dict)
    model_refs: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    reviews: Mapped[list[ReviewDecision]] = relationship(back_populates="finding", order_by="ReviewDecision.created_at", cascade="all, delete-orphan")


class ReviewDecision(Base):
    """Human review of a finding. Stored separately; the machine finding is never edited."""

    __tablename__ = "review_decisions"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("rev"))
    finding_id: Mapped[str] = mapped_column(ForeignKey("findings.id", ondelete="CASCADE"), index=True)
    action: Mapped[str] = mapped_column(String(32))
    resulting_verdict: Mapped[str | None] = mapped_column(String(16))
    corrected_value: Mapped[str | None] = mapped_column(String(255))
    reason: Mapped[str | None] = mapped_column(Text)
    notes: Mapped[str | None] = mapped_column(Text)
    reviewer: Mapped[str] = mapped_column(String(120))
    reviewer_kind: Mapped[str] = mapped_column(String(40), default="local-demo-identity")
    details: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    finding: Mapped[Finding] = relationship(back_populates="reviews")


class EvidenceAsset(Base):
    """A derived evidence artefact (annotated image, crop, overlay...). Bytes live in storage."""

    __tablename__ = "evidence_assets"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("evd"))
    inspection_id: Mapped[str] = mapped_column(ForeignKey("inspections.id", ondelete="CASCADE"), index=True)
    version_id: Mapped[str] = mapped_column(ForeignKey("inspection_versions.id", ondelete="CASCADE"), index=True)
    finding_id: Mapped[str | None] = mapped_column(ForeignKey("findings.id", ondelete="CASCADE"), nullable=True, index=True)
    kind: Mapped[str] = mapped_column(String(40), index=True)
    title: Mapped[str] = mapped_column(String(200))
    storage_key: Mapped[str | None] = mapped_column(String(255))
    content_type: Mapped[str | None] = mapped_column(String(100))
    width: Mapped[int | None] = mapped_column(Integer)
    height: Mapped[int | None] = mapped_column(Integer)
    sha256: Mapped[str | None] = mapped_column(String(64))
    bbox: Mapped[list | None] = mapped_column(JSON)
    source_asset_id: Mapped[str | None] = mapped_column(String(40))
    operation: Mapped[str] = mapped_column(String(120))
    algorithm: Mapped[str | None] = mapped_column(String(200))
    error: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Report(Base):
    __tablename__ = "reports"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("rpt"))
    inspection_id: Mapped[str] = mapped_column(ForeignKey("inspections.id", ondelete="CASCADE"), index=True)
    version_id: Mapped[str] = mapped_column(ForeignKey("inspection_versions.id", ondelete="CASCADE"), index=True)
    format: Mapped[str] = mapped_column(String(12))  # pdf | json | csv | xlsx
    storage_key: Mapped[str] = mapped_column(String(255))
    filename: Mapped[str] = mapped_column(String(255))
    size_bytes: Mapped[int] = mapped_column(Integer)
    sha256: Mapped[str] = mapped_column(String(64))
    pages: Mapped[int | None] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)


class VersionComparison(Base):
    __tablename__ = "version_comparisons"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("cmp"))
    inspection_id: Mapped[str] = mapped_column(ForeignKey("inspections.id", ondelete="CASCADE"), index=True)
    from_version_id: Mapped[str] = mapped_column(ForeignKey("inspection_versions.id", ondelete="CASCADE"))
    to_version_id: Mapped[str] = mapped_column(ForeignKey("inspection_versions.id", ondelete="CASCADE"))
    summary: Mapped[dict] = mapped_column(JSON, default=dict)
    items: Mapped[list] = mapped_column(JSON, default=list)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class ProcessingJob(Base):
    __tablename__ = "processing_jobs"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("job"))
    inspection_id: Mapped[str] = mapped_column(ForeignKey("inspections.id", ondelete="CASCADE"), index=True)
    version_id: Mapped[str] = mapped_column(ForeignKey("inspection_versions.id", ondelete="CASCADE"), index=True)
    status: Mapped[str] = mapped_column(String(16), index=True)  # queued|running|completed|failed|cancelled
    cancel_requested: Mapped[int] = mapped_column(Integer, default=0)
    current_stage: Mapped[str | None] = mapped_column(String(40))
    error: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    stages: Mapped[list[ProcessingStage]] = relationship(back_populates="job", order_by="ProcessingStage.order", cascade="all, delete-orphan")


class ProcessingStage(Base):
    __tablename__ = "processing_stages"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("stg"))
    job_id: Mapped[str] = mapped_column(ForeignKey("processing_jobs.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(40))
    title: Mapped[str] = mapped_column(String(120))
    order: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(16), default="pending")  # pending|running|completed|failed|skipped|needs_review
    message: Mapped[str | None] = mapped_column(Text)
    details: Mapped[dict] = mapped_column(JSON, default=dict)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    duration_ms: Mapped[int | None] = mapped_column(Integer)

    job: Mapped[ProcessingJob] = relationship(back_populates="stages")


class AuditEvent(Base):
    __tablename__ = "audit_events"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("aud"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)
    actor: Mapped[str] = mapped_column(String(120))
    event_type: Mapped[str] = mapped_column(String(60), index=True)
    entity_type: Mapped[str] = mapped_column(String(40))
    entity_id: Mapped[str] = mapped_column(String(40))
    inspection_id: Mapped[str | None] = mapped_column(ForeignKey("inspections.id", ondelete="CASCADE"), nullable=True, index=True)
    details: Mapped[dict] = mapped_column(JSON, default=dict)
    message: Mapped[str | None] = mapped_column(Text)
