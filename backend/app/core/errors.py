"""Consistent API error schema: {"error": {"code", "message", "details"}}."""
from __future__ import annotations

from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from .logging import get_logger

log = get_logger("api.errors")


class ApiError(Exception):
    def __init__(self, status_code: int, code: str, message: str, details: Any = None):
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details


def not_found(what: str, ident: Any) -> ApiError:
    return ApiError(404, "not_found", f"{what} '{ident}' was not found")


def bad_request(code: str, message: str, details: Any = None) -> ApiError:
    return ApiError(400, code, message, details)


def conflict(code: str, message: str, details: Any = None) -> ApiError:
    return ApiError(409, code, message, details)


def _body(code: str, message: str, details: Any = None) -> dict:
    return {"error": {"code": code, "message": message, "details": details}}


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def _api_error(_req: Request, exc: ApiError):
        return JSONResponse(status_code=exc.status_code, content=_body(exc.code, exc.message, exc.details))

    @app.exception_handler(HTTPException)
    async def _http_error(_req: Request, exc: HTTPException):
        return JSONResponse(status_code=exc.status_code, content=_body("http_error", str(exc.detail)))

    @app.exception_handler(RequestValidationError)
    async def _validation(_req: Request, exc: RequestValidationError):
        errs = [{"loc": list(e.get("loc", [])), "msg": e.get("msg"), "type": e.get("type")} for e in exc.errors()]
        return JSONResponse(status_code=422, content=_body("validation_error", "Request validation failed", errs))

    @app.exception_handler(Exception)
    async def _unhandled(_req: Request, exc: Exception):
        log.exception("Unhandled error: %s", type(exc).__name__)
        return JSONResponse(status_code=500, content=_body("internal_error", "An unexpected server error occurred. See server logs."))
