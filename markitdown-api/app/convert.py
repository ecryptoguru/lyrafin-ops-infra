import asyncio
import logging
import os
import shutil
import tempfile
import time
from pathlib import Path

from fastapi import File, HTTPException, UploadFile, status
from fastapi.responses import JSONResponse
from markitdown import MarkItDown

from .config import ALLOWED_EXTENSIONS, ALLOWED_MIME_TYPES, settings

logger = logging.getLogger(__name__)

GENERIC_MIME_TYPES = {"application/octet-stream", "binary/octet-stream"}

_mkd: MarkItDown | None = None


def get_markitdown() -> MarkItDown:
    global _mkd
    if _mkd is None:
        kwargs = {}
        if settings.azure_document_intelligence_endpoint:
            kwargs["docintel_endpoint"] = settings.azure_document_intelligence_endpoint
        _mkd = MarkItDown(**kwargs)
    return _mkd


def _sanitize_filename(filename: str) -> str:
    safe = os.path.basename(filename)
    if not safe or safe in (".", ".."):
        safe = "upload"
    return safe


def _validate_file(filename: str, content_type: str, file_size: int) -> None:
    if file_size > settings.max_file_size_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"File size exceeds {settings.max_file_size_mb} MB limit",
        )

    ext = Path(filename).suffix.lower()
    if not ext:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="File must have an extension",
        )
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported file extension: {ext}",
        )

    if content_type and content_type not in ALLOWED_MIME_TYPES:
        if content_type not in GENERIC_MIME_TYPES:
            raise HTTPException(
                status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                detail=f"Unsupported MIME type: {content_type}",
            )


async def _convert_with_timeout(file_path: str) -> str:
    mkd = get_markitdown()
    result = await asyncio.to_thread(mkd.convert, file_path)
    return result.text_content


async def convert_file(file: UploadFile = File(...)) -> JSONResponse:
    raw_filename = file.filename or "unknown"
    content_type = file.content_type or ""

    content = await file.read()
    file_size = len(content)

    filename = _sanitize_filename(raw_filename)
    _validate_file(filename, content_type, file_size)

    tmp_dir = tempfile.mkdtemp(prefix="markitdown_")
    tmp_path = os.path.join(tmp_dir, filename)

    try:
        with open(tmp_path, "wb") as f:
            f.write(content)

        start_time = time.monotonic()
        try:
            text = await asyncio.wait_for(
                _convert_with_timeout(tmp_path),
                timeout=settings.conversion_timeout_seconds,
            )
        except asyncio.TimeoutError:
            raise HTTPException(
                status_code=status.HTTP_504_GATEWAY_TIMEOUT,
                detail=f"Conversion timed out after {settings.conversion_timeout_seconds}s",
            )
        except Exception as e:
            logger.error("Conversion failed for %s: %s", filename, type(e).__name__)
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Conversion failed: {type(e).__name__}",
            )

        duration_ms = int((time.monotonic() - start_time) * 1000)

        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={
                "filename": raw_filename,
                "content_type": content_type,
                "size_bytes": file_size,
                "text": text,
                "duration_ms": duration_ms,
            },
        )
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


async def health() -> dict:
    return {
        "status": "ok",
        "azure_doc_intel": bool(settings.azure_document_intelligence_endpoint),
    }
