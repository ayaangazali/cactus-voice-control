from __future__ import annotations

from fastapi import Header, HTTPException, status


def verify_bearer(expected_token: str):
    async def _verify(authorization: str | None = Header(default=None)):
        if expected_token is None or expected_token == "":
            raise HTTPException(status_code=500, detail="Server has no CACTUS_TOKEN configured.")
        if not authorization or not authorization.lower().startswith("bearer "):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Missing or malformed Authorization header.",
            )
        provided = authorization.split(" ", 1)[1].strip()
        if not _safe_compare(provided, expected_token):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Bad token.")
        return True

    return _verify


def _safe_compare(a: str, b: str) -> bool:
    if len(a) != len(b):
        return False
    diff = 0
    for x, y in zip(a, b):
        diff |= ord(x) ^ ord(y)
    return diff == 0
