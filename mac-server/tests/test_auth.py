import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from cactus_voice_mac.auth import _safe_compare, verify_bearer


def make_app(token: str) -> FastAPI:
    app = FastAPI()
    dep = verify_bearer(token)

    @app.get("/x")
    async def x(_: bool = __import__("fastapi").Depends(dep)):
        return {"ok": True}

    return app


def test_safe_compare_equal():
    assert _safe_compare("abc", "abc") is True


def test_safe_compare_diff_len():
    assert _safe_compare("abc", "abcd") is False


def test_safe_compare_diff_value():
    assert _safe_compare("abc", "abd") is False


def test_missing_header_returns_401():
    client = TestClient(make_app("secret"))
    r = client.get("/x")
    assert r.status_code == 401


def test_bad_token_returns_401():
    client = TestClient(make_app("secret"))
    r = client.get("/x", headers={"Authorization": "Bearer wrong"})
    assert r.status_code == 401


def test_good_token_passes():
    client = TestClient(make_app("secret"))
    r = client.get("/x", headers={"Authorization": "Bearer secret"})
    assert r.status_code == 200
    assert r.json() == {"ok": True}


def test_empty_server_token_returns_500():
    client = TestClient(make_app(""))
    r = client.get("/x", headers={"Authorization": "Bearer anything"})
    assert r.status_code == 500
