from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from uuid import UUID

from fastapi import Depends, FastAPI, HTTPException
from sse_starlette.sse import EventSourceResponse

from .auth import verify_bearer
from .models import CommandIntent, Phase
from .runner import Runner

log = logging.getLogger("cactus_voice_mac")

TERMINAL_PHASES = {Phase.SUCCEEDED, Phase.FAILED, Phase.CANCELLED}


def create_app(
    *,
    token: str,
    mobile_use_cmd: str,
    target_udid: str | None = None,
) -> FastAPI:
    runner = Runner(mobile_use_cmd=mobile_use_cmd, target_udid=target_udid)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        log.info("cactus-voice-mac starting; mobile_use_cmd=%s", mobile_use_cmd)
        yield
        for state in list(runner.jobs.values()):
            if state.process and state.process.returncode is None:
                state.process.terminate()

    app = FastAPI(title="Cactus Voice Mac Gateway", version="0.1.0", lifespan=lifespan)
    requires_auth = Depends(verify_bearer(token))

    @app.get("/health")
    async def health(_: bool = requires_auth):
        return {"ok": True, "version": "0.1.0", "jobs": len(runner.jobs)}

    @app.post("/command")
    async def command(intent: CommandIntent, _: bool = requires_auth):
        state = await runner.start(intent)
        return state.to_status()

    @app.get("/status/{job_id}")
    async def status_stream(job_id: str, _: bool = requires_auth):
        try:
            uid = UUID(job_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="bad uuid")

        async def event_gen():
            async for status in runner.subscribe(uid):
                yield {"data": status.model_dump_json()}
                if status.phase in TERMINAL_PHASES:
                    return

        return EventSourceResponse(event_gen())

    @app.post("/cancel/{job_id}")
    async def cancel(job_id: str, _: bool = requires_auth):
        try:
            uid = UUID(job_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="bad uuid")
        ok = await runner.cancel(uid)
        return {"cancelled": ok}

    return app


def app_from_env() -> FastAPI:
    from dotenv import load_dotenv

    load_dotenv()
    token = os.environ.get("CACTUS_TOKEN", "")
    if not token or token == "changeme-generate-with-secrets-module":
        raise RuntimeError(
            "Set CACTUS_TOKEN in .env. Generate with: python -c 'import secrets; print(secrets.token_urlsafe(32))'"
        )
    cmd = os.environ.get("MOBILE_USE_CMD", "uv run mobile-use")
    udid = os.environ.get("TARGET_UDID") or None
    return create_app(token=token, mobile_use_cmd=cmd, target_udid=udid)
