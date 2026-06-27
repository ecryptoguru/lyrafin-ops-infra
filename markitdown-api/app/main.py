import logging

from fastapi import Depends, FastAPI, File, UploadFile

from .convert import convert_file, health
from .security import verify_api_key

logging.basicConfig(level=logging.INFO)

app = FastAPI(
    title="Lyrafin MarkItDown API",
    description="Private document-to-markdown conversion service for Lyrafin AI",
    version="1.0.0",
)


@app.get("/health")
async def health_endpoint():
    return await health()


@app.post("/v1/convert/file")
async def convert_file_endpoint(file: UploadFile = File(...), _: None = Depends(verify_api_key)):
    return await convert_file(file)


@app.post("/v1/convert/blob")
async def convert_blob_endpoint(file: UploadFile = File(...), _: None = Depends(verify_api_key)):
    return await convert_file(file)


# v1 does not include POST /v1/convert/url — SSRF risk, add later with allowlisting
