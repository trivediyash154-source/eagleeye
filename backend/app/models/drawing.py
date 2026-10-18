from __future__ import annotations

from datetime import datetime

from sqlalchemy import JSON, DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.db import Base
from ..core.util import new_id, utcnow


class Drawing(Base):
    """Parsed GA drawing page. Coordinates are PDF points, origin top-left, y down."""

    __tablename__ = "drawings"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("dwg"))
    version_id: Mapped[str] = mapped_column(ForeignKey("inspection_versions.id", ondelete="CASCADE"), index=True)
    asset_id: Mapped[str] = mapped_column(ForeignKey("input_assets.id", ondelete="CASCADE"))
    page_index: Mapped[int] = mapped_column(Integer, default=0)
    page_count: Mapped[int] = mapped_column(Integer, default=1)
    page_width: Mapped[float] = mapped_column(Float)
    page_height: Mapped[float] = mapped_column(Float)
    content_kind: Mapped[str] = mapped_column(String(16))  # vector | raster | mixed | empty
    render_storage_key: Mapped[str | None] = mapped_column(String(255))
    render_scale: Mapped[float] = mapped_column(Float, default=1.0)  # render px per PDF point
    text_spans: Mapped[list] = mapped_column(JSON, default=list)
    rects: Mapped[list] = mapped_column(JSON, default=list)
    warnings: Mapped[list] = mapped_column(JSON, default=list)
    stats: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    zones: Mapped[list[DrawingZone]] = relationship(back_populates="drawing", cascade="all, delete-orphan", order_by="DrawingZone.code")


class DrawingZone(Base):
    __tablename__ = "drawing_zones"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("zone"))
    drawing_id: Mapped[str] = mapped_column(ForeignKey("drawings.id", ondelete="CASCADE"), index=True)
    code: Mapped[str] = mapped_column(String(40))
    name: Mapped[str | None] = mapped_column(String(200))
    x0: Mapped[float] = mapped_column(Float)
    y0: Mapped[float] = mapped_column(Float)
    x1: Mapped[float] = mapped_column(Float)
    y1: Mapped[float] = mapped_column(Float)
    source: Mapped[str] = mapped_column(String(32))  # drawing_frame | derived_from_components | manual
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    drawing: Mapped[Drawing] = relationship(back_populates="zones")


class ExpectedComponent(Base):
    """A component the engineering specification says must be in the cabinet."""

    __tablename__ = "expected_components"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("exc"))
    version_id: Mapped[str] = mapped_column(ForeignKey("inspection_versions.id", ondelete="CASCADE"), index=True)
    tag: Mapped[str] = mapped_column(String(120), index=True)
    zone_code: Mapped[str | None] = mapped_column(String(40))
    component_type: Mapped[str | None] = mapped_column(String(120))
    canonical_class: Mapped[str | None] = mapped_column(String(60))
    expected_label: Mapped[str | None] = mapped_column(String(120))
    quantity: Mapped[int] = mapped_column(Integer, default=1)
    notes: Mapped[str | None] = mapped_column(Text)
    source_sheet: Mapped[str | None] = mapped_column(String(120))
    source_row: Mapped[int | None] = mapped_column(Integer)
    drawing_bbox: Mapped[list | None] = mapped_column(JSON)  # component body in drawing points
    drawing_label_bbox: Mapped[list | None] = mapped_column(JSON)  # designation label in drawing points
    drawing_match: Mapped[str | None] = mapped_column(String(40))  # how it was located in the drawing


class ExpectedIdentifier(Base):
    """Expected ferrule / terminal / wire record from the wire list."""

    __tablename__ = "expected_identifiers"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("exi"))
    version_id: Mapped[str] = mapped_column(ForeignKey("inspection_versions.id", ondelete="CASCADE"), index=True)
    component_tag: Mapped[str | None] = mapped_column(String(120))
    zone_code: Mapped[str | None] = mapped_column(String(40))
    kind: Mapped[str] = mapped_column(String(24))  # ferrule | terminal
    value: Mapped[str | None] = mapped_column(String(120))  # expected ferrule text
    terminal_ref: Mapped[str | None] = mapped_column(String(120))
    wire_color: Mapped[str | None] = mapped_column(String(60))
    source_sheet: Mapped[str | None] = mapped_column(String(120))
    source_row: Mapped[int | None] = mapped_column(Integer)
    drawing_bbox: Mapped[list | None] = mapped_column(JSON)  # ferrule marker in drawing points
    drawing_terminal_bbox: Mapped[list | None] = mapped_column(JSON)  # terminal below the marker, if located
    drawing_match: Mapped[str | None] = mapped_column(String(40))
