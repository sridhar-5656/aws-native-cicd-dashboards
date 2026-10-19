"""FastAPI application factory."""
from __future__ import annotations

import logging
import time
import uuid
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.config import Settings, get_settings
from app.logging_config import configure_logging
from app.routers import health, info
from app.schemas import RootResponse
from app.state import RuntimeState, frontend_assets_present

logger = logging.getLogger("app")

ENDPOINTS = ["/", "/health", "/health/live", "/health/ready", "/api/info", "/api/status"]
QUIET_PATHS = {"/health", "/health/live", "/health/ready"}  # ALB polls these every ~30s


def _error(status_code: int, code: str, message: str, details: Optional[list] = None) -> JSONResponse:
    body = {"error": {"code": code, "message": message}}
    if details:
        body["error"]["details"] = details
    return JSONResponse(status_code=status_code, content=body)


def create_app(settings: Optional[Settings] = None) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level)
    runtime = RuntimeState()

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        runtime.startup_complete = True
        logger.info(
            "application started",
            extra={"version": settings.version, "environment": settings.environment,
                   "release_id": settings.effective_release_id},
        )
        yield
        runtime.shutting_down = True
        logger.info("application shutting down")

    app = FastAPI(
        title=settings.name,
        version=settings.version,
        lifespan=lifespan,
        docs_url="/docs" if settings.enable_docs else None,
        redoc_url=None,
        openapi_url="/openapi.json" if settings.enable_docs else None,
    )
    app.state.settings = settings
    app.state.runtime = runtime

    # ---- middleware: request id, access log, security headers -------------
    @app.middleware("http")
    async def request_context(request: Request, call_next):
        runtime.request_count += 1
        request_id = request.headers.get("x-request-id") or uuid.uuid4().hex
        start = time.perf_counter()
        response = await call_next(request)
        duration_ms = round((time.perf_counter() - start) * 1000, 2)
        level = logging.DEBUG if request.url.path in QUIET_PATHS else logging.INFO
        logger.log(
            level, "request",
            extra={"method": request.method, "path": request.url.path,
                   "status": response.status_code, "duration_ms": duration_ms,
                   "request_id": request_id},
        )
        response.headers["X-Request-ID"] = request_id
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        if not settings.enable_docs:
            response.headers["Content-Security-Policy"] = (
                "default-src 'self'; img-src 'self' data:; frame-ancestors 'none'"
            )
        return response

    # ---- centralized error handling (never leaks internals) ---------------
    @app.exception_handler(StarletteHTTPException)
    async def http_exception_handler(_: Request, exc: StarletteHTTPException):
        code = {404: "not_found", 405: "method_not_allowed"}.get(exc.status_code, "http_error")
        return _error(exc.status_code, code, str(exc.detail))

    @app.exception_handler(RequestValidationError)
    async def validation_handler(_: Request, exc: RequestValidationError):
        details = [{"loc": list(e["loc"]), "msg": e["msg"], "type": e["type"]} for e in exc.errors()]
        return _error(422, "validation_error", "Request validation failed", details)

    @app.exception_handler(Exception)
    async def unhandled_handler(request: Request, exc: Exception):
        logger.exception("unhandled error", extra={"path": request.url.path})
        return _error(500, "internal_error", "Internal server error")

    # ---- routes -----------------------------------------------------------
    app.include_router(health.router)
    app.include_router(info.router)

    @app.get("/", include_in_schema=False)
    def root(request: Request):
        accept = request.headers.get("accept", "")
        wants_json = "application/json" in accept and "text/html" not in accept
        index = settings.static_dir / "index.html"
        if not wants_json and index.is_file():
            return FileResponse(index, media_type="text/html")
        return JSONResponse(
            RootResponse(
                name=settings.name,
                version=settings.version,
                message="API is running" + ("" if index.is_file() else " (frontend build not found)"),
                endpoints=ENDPOINTS,
            ).model_dump()
        )

    if frontend_assets_present(settings.static_dir):
        assets = settings.static_dir / "assets"
        if assets.is_dir():
            app.mount("/assets", StaticFiles(directory=assets), name="assets")

        @app.get("/favicon.svg", include_in_schema=False)
        def favicon():
            return FileResponse(settings.static_dir / "favicon.svg", media_type="image/svg+xml")

    return app


app = create_app()
