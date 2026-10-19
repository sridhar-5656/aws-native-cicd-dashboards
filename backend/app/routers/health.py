"""Health endpoints.

* /health/live  - process is up. Never depends on optional dependencies.
* /health/ready - safe to receive traffic (used by the ALB target group).
"""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Request, Response, status

from app.schemas import HealthResponse, LivenessResponse, ReadinessResponse
from app.state import frontend_assets_present

router = APIRouter(prefix="/health", tags=["health"])


def _now() -> datetime:
    return datetime.now(timezone.utc)


def compute_readiness_checks(request: Request) -> dict[str, bool]:
    settings = request.app.state.settings
    state = request.app.state.runtime
    checks = {
        "startup_complete": state.startup_complete,
        "not_shutting_down": not state.shutting_down,
    }
    if settings.require_frontend:
        checks["frontend_assets"] = frontend_assets_present(settings.static_dir)
    return checks


@router.get("", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(status="ok", timestamp=_now())


@router.get("/live", response_model=LivenessResponse)
def live() -> LivenessResponse:
    return LivenessResponse(status="alive", timestamp=_now())


@router.get("/ready", response_model=ReadinessResponse)
def ready(request: Request, response: Response) -> ReadinessResponse:
    checks = compute_readiness_checks(request)
    is_ready = all(checks.values())
    if not is_ready:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return ReadinessResponse(
        status="ready" if is_ready else "not_ready", checks=checks, timestamp=_now()
    )
