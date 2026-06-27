import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_convert_file_no_api_key():
    resp = client.post("/v1/convert/file", files={"file": ("test.txt", b"hello", "text/plain")})
    assert resp.status_code == 401


def test_convert_file_bad_api_key():
    resp = client.post(
        "/v1/convert/file",
        files={"file": ("test.txt", b"hello", "text/plain")},
        headers={"X-API-Key": "wrong-key"},
    )
    assert resp.status_code == 401


def test_convert_file_unsupported_extension():
    resp = client.post(
        "/v1/convert/file",
        files={"file": ("test.exe", b"\x00\x00", "application/octet-stream")},
        headers={"X-API-Key": "local-dev-token"},
    )
    assert resp.status_code == 415


def test_convert_file_oversized():
    large_content = b"x" * (51 * 1024 * 1024)
    resp = client.post(
        "/v1/convert/file",
        files={"file": ("large.txt", large_content, "text/plain")},
        headers={"X-API-Key": "local-dev-token"},
    )
    assert resp.status_code == 413


def test_convert_text_file():
    resp = client.post(
        "/v1/convert/file",
        files={"file": ("test.txt", b"Hello, Lyrafin!", "text/plain")},
        headers={"X-API-Key": "local-dev-token"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "text" in data
    assert "duration_ms" in data
    assert data["filename"] == "test.txt"


def test_convert_no_extension_rejected():
    resp = client.post(
        "/v1/convert/file",
        files={"file": ("noextension", b"hello", "text/plain")},
        headers={"X-API-Key": "local-dev-token"},
    )
    assert resp.status_code == 415


def test_convert_generic_mime_fallback():
    resp = client.post(
        "/v1/convert/file",
        files={"file": ("test.csv", b"a,b,c\n1,2,3", "application/octet-stream")},
        headers={"X-API-Key": "local-dev-token"},
    )
    assert resp.status_code == 200
    assert "text" in resp.json()


def test_convert_path_traversal_sanitized():
    resp = client.post(
        "/v1/convert/file",
        files={"file": ("../../../etc/passwd", b"root:x:0:0", "text/plain")},
        headers={"X-API-Key": "local-dev-token"},
    )
    # Should not write outside temp dir; .passwd is not an allowed extension
    assert resp.status_code == 415


def test_convert_blob_endpoint():
    resp = client.post(
        "/v1/convert/blob",
        files={"file": ("test.txt", b"blob test", "text/plain")},
        headers={"X-API-Key": "local-dev-token"},
    )
    assert resp.status_code == 200
    assert resp.json()["text"] == "blob test"
