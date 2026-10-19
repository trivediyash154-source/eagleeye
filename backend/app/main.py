"""EAGLE EYE API application."""
from __future__ import annotations

import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse

# Ultralytics must not pip-install packages or contact its servers at runtime.
os.environ.setdefault("YOLO_AUTOINSTALL", "false")
os.environ.setdefault("YOLO_OFFLINE", "1")

from .core.config import BACKEND_DIR, get_settings  # noqa: E402
from .core.errors import install_error_handlers  # noqa: E402
from .core.logging import configure_logging, get_logger  # noqa: E402

configure_logging()
log = get_logger("app")


def run_migrations() -> None:
    from alembic import command
    from alembic.config import Config

    cfg = Config(str(BACKEND_DIR / "alembic.ini"))
    cfg.set_main_option("script_location", str(BACKEND_DIR / "migrations"))
    cfg.set_main_option("sqlalchemy.url", get_settings().resolved_database_url.replace("%", "%%"))
    command.upgrade(cfg, "head")


@asynccontextmanager
async def lifespan(app: FastAPI):
    s = get_settings()
    if s.auto_migrate:
        run_migrations()
    from .services.diagnostics import warm_models_async
    from .workers.jobs import recover_jobs, shutdown

    recover_jobs()
    if s.environment != "test":
        warm_models_async()
    log.info("EAGLE EYE API started", extra={"ctx": {"environment": s.environment, "db": "sqlite" if s.is_sqlite else "postgresql"}})
    yield
    shutdown()


def create_app() -> FastAPI:
    s = get_settings()
    app = FastAPI(
        title="EAGLE EYE API",
        version="1.0.0",
        description="Drawing-aware industrial cabinet inspection: uploads, pipeline jobs, findings, evidence, reviews, versioning, reports and diagnostics.",
        lifespan=lifespan,
        openapi_url=f"/api/{s.api_version}/openapi.json",
        docs_url=f"/api/{s.api_version}/docs",
        redoc_url=None,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=s.cors_origins,
        allow_origin_regex=r"^http://(localhost|127\.0\.0\.1)(:\d+)?$" if s.environment == "development" else None,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
        allow_headers=["Content-Type", "Authorization"],
        expose_headers=["Content-Disposition"],
    )

    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        resp = await call_next(request)
        resp.headers.setdefault("X-Content-Type-Options", "nosniff")
        resp.headers.setdefault("Referrer-Policy", "no-referrer")
        resp.headers.setdefault("X-Frame-Options", "SAMEORIGIN")
        return resp

    install_error_handlers(app)
    from .api import routes_demo, routes_findings, routes_inspections, routes_system

    prefix = f"/api/{s.api_version}"
    for r in (routes_system.router, routes_inspections.router, routes_findings.router, routes_demo.router):
        app.include_router(r, prefix=prefix)

    dist = s.resolved_frontend_dist
    if dist is not None:
        root = dist.resolve()
        log.info("Serving web console", extra={"ctx": {"dir": str(root)}})

        @app.get("/{full_path:path}", include_in_schema=False)
        async def spa(full_path: str):
            if full_path.startswith("api/"):
                return JSONResponse({"error": {"code": "not_found", "message": "Unknown API route", "details": None}}, status_code=404)
            target = (root / full_path).resolve()
            if full_path and root in target.parents and target.is_file():
                return FileResponse(target)
            return FileResponse(root / "index.html", headers={"Cache-Control": "no-cache"})

    return app


app = create_app()
