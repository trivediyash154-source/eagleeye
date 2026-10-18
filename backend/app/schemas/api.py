"""Explicit API schemas (v1). The Flutter client mirrors these in lib/core/api/models.dart."""
from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field

Verdict = Literal["PASS", "FAIL", "UNCERTAIN"]


class ErrorBody(BaseModel):
    code: str
    message: str
    details: Any | None = None


class ErrorResponse(BaseModel):
    error: ErrorBody


# --- inspections -------------------------------------------------------------

class InspectionCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    cabinet_id: str = Field(min_length=1, max_length=120)
    site: str | None = Field(default=None, max_length=200)
    reference: str | None = Field(default=None, max_length=120)
    inspector: str | None = Field(default=None, max_length=120)
    project_ref: str | None = Field(default=None, max_length=120)
    notes: str | None = Field(default=None, max_length=5000)


class InspectionUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    site: str | None = Field(default=None, max_length=200)
    reference: str | None = Field(default=None, max_length=120)
    inspector: str | None = Field(default=None, max_length=120)
    project_ref: str | None = Field(default=None, max_length=120)
    notes: str | None = Field(default=None, max_length=5000)


class Summary(BaseModel):
    total: int = 0
    pass_: int = Field(0, alias="pass")
    fail: int = 0
    uncertain: int = 0
    by_check: dict[str, dict[str, int]] = {}
    registration: str | None = None
    detector_kind: str | None = None
    targeted_ocr_reads: int | None = None

    model_config = {"populate_by_name": True}


class AssetOut(BaseModel):
    id: str
    kind: str
    original_filename: str
    content_type: str
    size_bytes: int
    sha256: str
    analysis: dict[str, Any]
    created_at: str
    inherited: bool
    download_url: str


class VersionOut(BaseModel):
    id: str
    inspection_id: str
    version_no: int
    label: str
    parent_version_id: str | None
    status: str
    config: dict[str, Any]
    summary: dict[str, Any]
    effective_summary: dict[str, int]
    registration: dict[str, Any]
    preprocessing: dict[str, Any]
    error: str | None
    created_at: str
    started_at: str | None
    completed_at: str | None
    duration_ms: int | None
    assets: list[AssetOut]
    latest_job_id: str | None
    reviewed_count: int
    finding_count: int


class InspectionOut(BaseModel):
    id: str
    code: str
    title: str
    cabinet_id: str
    site: str | None
    reference: str | None
    inspector: str | None
    project_ref: str | None
    notes: str | None
    is_demo: bool
    created_at: str
    updated_at: str
    version_count: int
    latest_version: VersionOut | None


class InspectionDetail(InspectionOut):
    versions: list[VersionOut]


class InspectionList(BaseModel):
    items: list[InspectionOut]
    total: int
    page: int
    page_size: int


class VersionConfigUpdate(BaseModel):
    checks: list[str] | None = None
    drawing_page: int | None = Field(default=None, ge=0, le=500)
    sheets: list[dict[str, Any]] | None = None
    preprocess: dict[str, bool] | None = None
    detector: dict[str, Any] | None = None
    policies: dict[str, dict[str, Any]] | None = None


class ReadinessItem(BaseModel):
    key: str
    label: str
    status: Literal["ok", "warning", "error"]
    message: str


class Readiness(BaseModel):
    ready: bool
    items: list[ReadinessItem]


# --- jobs ----------------------------------------------------------------------

class StageOut(BaseModel):
    name: str
    title: str
    order: int
    status: str
    message: str | None
    details: dict[str, Any]
    started_at: str | None
    finished_at: str | None
    duration_ms: int | None


class JobOut(BaseModel):
    id: str
    inspection_id: str
    version_id: str
    status: str
    cancel_requested: bool
    current_stage: str | None
    error: str | None
    created_at: str
    started_at: str | None
    finished_at: str | None
    stages: list[StageOut]


# --- findings --------------------------------------------------------------------

class ReviewIn(BaseModel):
    action: Literal["confirm", "resolve_pass", "resolve_fail", "false_positive", "correct_observed", "mark_reviewed", "waive", "note"]
    notes: str | None = Field(default=None, max_length=5000)
    reason: str | None = Field(default=None, max_length=2000)
    corrected_value: str | None = Field(default=None, max_length=255)


class ReviewOut(BaseModel):
    id: str
    finding_id: str
    action: str
    resulting_verdict: str | None
    corrected_value: str | None
    reason: str | None
    notes: str | None
    reviewer: str
    reviewer_kind: str
    details: dict[str, Any]
    created_at: str


class EvidenceOut(BaseModel):
    id: str
    inspection_id: str
    version_id: str
    finding_id: str | None
    kind: str
    title: str
    content_type: str | None
    width: int | None
    height: int | None
    sha256: str | None
    bbox: list[float] | None
    source_asset_id: str | None
    operation: str
    algorithm: str | None
    error: str | None
    created_at: str
    url: str | None
    thumbnail_url: str | None


class FindingOut(BaseModel):
    id: str
    inspection_id: str
    version_id: str
    version_no: int | None = None
    seq: int
    finding_key: str
    check_type: str
    zone_code: str | None
    subject: str
    expected_value: str | None
    observed_value: str | None
    observed_raw: str | None
    verdict: Verdict
    effective_verdict: str
    review_status: str
    rule: str
    explanation: str
    confidences: dict[str, Any]
    review_reasons: list[str]
    bbox: list[float] | None
    expected_bbox: list[float] | None
    drawing_bbox: list[float] | None
    detection_id: str | None
    ocr_observation_id: str | None
    model_refs: dict[str, Any]
    created_at: str
    review_count: int


class FindingDetail(FindingOut):
    details: dict[str, Any]
    reviews: list[ReviewOut]
    evidence: list[EvidenceOut]
    detection: dict[str, Any] | None
    ocr_observation: dict[str, Any] | None
    history: list[dict[str, Any]]


class FindingList(BaseModel):
    items: list[FindingOut]
    total: int
    counts: dict[str, int]


# --- drawing ------------------------------------------------------------------------

class ZoneOut(BaseModel):
    id: str
    code: str
    name: str | None
    bbox: list[float]
    source: str
    notes: str | None
    projected_quad: list[list[float]] | None


class ZoneIn(BaseModel):
    code: str = Field(min_length=1, max_length=40)
    name: str | None = Field(default=None, max_length=200)
    bbox: list[float] = Field(min_length=4, max_length=4)


class ZonesUpdate(BaseModel):
    zones: list[ZoneIn]


class AnchorPair(BaseModel):
    drawing: list[float] = Field(min_length=2, max_length=2)
    photo: list[float] = Field(min_length=2, max_length=2)
    label: str | None = None


class ManualAlignmentIn(BaseModel):
    anchors: list[AnchorPair] = Field(min_length=4, max_length=40)
    rerun: bool = True


class ReinspectionIn(BaseModel):
    label: str | None = Field(default=None, max_length=120)
    reuse_photo: bool = False


class SampleInspectionIn(BaseModel):
    variant: Literal["v1", "v2"] = "v1"
    run: bool = True
