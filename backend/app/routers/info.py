"""Application metadata and status endpoints."""
from __future__ import annotations

import platform
from datetime import datetime, timezone

from fastapi import APIRouter, Query, Request

from app.routers.health import compute_readiness_checks
from app.schemas import InfoResponse, StatusResponse
from app.state import frontend_assets_present

router = APIRouter(prefix="/api", tags=["api"])


@router.get("/info", response_model=InfoResponse)
def info(request: Request) -> InfoResponse:
    s = request.app.state.settings
    state = request.app.state.runtime
    return InfoResponse(
        name=s.name,
        version=s.version,
        environment=s.environment,
        release_id=s.effective_release_id,
        git_commit=s.git_commit,
        image_tag=s.image_tag,
        build_time=s.build_time,
        started_at=state.started_at,
        python_version=platform.python_version(),
        unavailable=[
            "pipeline_execution_status",
            "aws_account_details",
            "ecs_task_metadata",
        ],
    )


@router.get("/status", response_model=StatusResponse)
def status_endpoint(
    request: Request,
    include_checks: bool = Query(True, description="Include readiness check details"),
) -> StatusResponse:
    state = request.app.state.runtime
    checks = compute_readiness_checks(request)
    checks["frontend_assets"] = frontend_assets_present(request.app.state.settings.static_dir)
    ok = all(v for k, v in checks.items() if k != "frontend_assets") or False
    return StatusResponse(
        status="ok" if ok else "degraded",
        uptime_seconds=state.uptime_seconds,
        started_at=state.started_at,
        timestamp=datetime.now(timezone.utc),
        checks=checks if include_checks else None,
        request_count=state.request_count,
        memory_mb=state.memory_mb,
    )
