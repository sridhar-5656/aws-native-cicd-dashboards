"""Typed response models."""
from __future__ import annotations

from datetime import datetime
from typing import Dict, List, Literal, Optional

from pydantic import BaseModel


class RootResponse(BaseModel):
    name: str
    version: str
    message: str
    endpoints: List[str]


class HealthResponse(BaseModel):
    status: Literal["ok"]
    timestamp: datetime


class LivenessResponse(BaseModel):
    status: Literal["alive"]
    timestamp: datetime


class ReadinessResponse(BaseModel):
    status: Literal["ready", "not_ready"]
    checks: Dict[str, bool]
    timestamp: datetime


class InfoResponse(BaseModel):
    name: str
    version: str
    environment: str
    release_id: str
    git_commit: Optional[str]
    image_tag: Optional[str]
    build_time: Optional[str]
    started_at: datetime
    python_version: str
    # Honest list of facts this service CANNOT know at runtime.
    unavailable: List[str]


class StatusResponse(BaseModel):
    status: Literal["ok", "degraded"]
    uptime_seconds: float
    started_at: datetime
    timestamp: datetime
    checks: Optional[Dict[str, bool]] = None
    request_count: Optional[int] = None
    memory_mb: Optional[float] = None


class ErrorDetail(BaseModel):
    code: str
    message: str
    details: Optional[list] = None


class ErrorResponse(BaseModel):
    error: ErrorDetail
