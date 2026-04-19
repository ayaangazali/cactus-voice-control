from __future__ import annotations

import asyncio
import os
import shlex
from collections import deque
from dataclasses import dataclass, field
from typing import AsyncIterator
from uuid import UUID

from .models import CommandIntent, CommandStatus, Phase


@dataclass
class JobState:
    id: UUID
    intent: CommandIntent
    phase: Phase = Phase.RECEIVED
    message: str | None = None
    result: str | None = None
    log_lines: deque[str] = field(default_factory=lambda: deque(maxlen=2000))
    process: asyncio.subprocess.Process | None = None
    listeners: list[asyncio.Queue[CommandStatus]] = field(default_factory=list)

    def to_status(self) -> CommandStatus:
        return CommandStatus(id=self.id, phase=self.phase, message=self.message, result=self.result)


class Runner:
    """Manages mobile-use subprocess lifecycle per intent."""

    def __init__(self, mobile_use_cmd: str, target_udid: str | None = None):
        self.mobile_use_cmd = mobile_use_cmd
        self.target_udid = target_udid or None
        self.jobs: dict[UUID, JobState] = {}
        self._lock = asyncio.Lock()

    def build_argv(self, intent: CommandIntent) -> list[str]:
        argv = shlex.split(self.mobile_use_cmd) + [intent.instruction]
        if intent.output_description:
            argv += ["--output-description", intent.output_description]
        # mobile-use needs WebDriverAgent up to drive iOS Simulator/device.
        # These flags spin up iproxy + WDA automatically on first run.
        argv += ["--wda-auto-start-iproxy", "--wda-auto-start-wda"]
        return argv

    def build_env(self) -> dict[str, str]:
        """Build subprocess environment.

        Forces unbuffered Python output so SSE consumers see status changes
        promptly, and disables mobile-use's interactive telemetry prompt.
        """
        env = os.environ.copy()
        env["PYTHONUNBUFFERED"] = "1"
        env.setdefault("MOBILE_USE_TELEMETRY_ENABLED", "false")
        return env

    async def start(self, intent: CommandIntent) -> JobState:
        async with self._lock:
            if intent.id in self.jobs:
                return self.jobs[intent.id]
            state = JobState(id=intent.id, intent=intent)
            self.jobs[intent.id] = state

        argv = self.build_argv(intent)
        try:
            proc = await asyncio.create_subprocess_exec(
                *argv,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
                env=self.build_env(),
            )
        except FileNotFoundError as e:
            state.phase = Phase.FAILED
            state.message = f"mobile-use not found: {e}"
            await self._notify(state)
            return state

        state.process = proc
        state.phase = Phase.RUNNING
        await self._notify(state)
        asyncio.create_task(self._reap(state))
        return state

    async def _reap(self, state: JobState) -> None:
        assert state.process is not None
        proc = state.process
        assert proc.stdout is not None
        try:
            async for raw in proc.stdout:
                line = raw.decode("utf-8", errors="replace").rstrip("\n")
                state.log_lines.append(line)
        except Exception as e:
            state.log_lines.append(f"[reader error] {e}")
        rc = await proc.wait()
        state.result = "\n".join(list(state.log_lines)[-50:])
        state.phase = Phase.SUCCEEDED if rc == 0 else Phase.FAILED
        if rc != 0:
            state.message = f"mobile-use exited with code {rc}"
        await self._notify(state)
        # _notify already drains state.listeners; previous code looped a second time.

    async def cancel(self, job_id: UUID) -> bool:
        state = self.jobs.get(job_id)
        if not state or state.process is None:
            return False
        state.process.terminate()
        try:
            await asyncio.wait_for(state.process.wait(), timeout=5)
        except asyncio.TimeoutError:
            state.process.kill()
        state.phase = Phase.CANCELLED
        state.message = "cancelled"
        await self._notify(state)
        return True

    async def subscribe(self, job_id: UUID) -> AsyncIterator[CommandStatus]:
        state = self.jobs.get(job_id)
        if state is None:
            return
        q: asyncio.Queue[CommandStatus] = asyncio.Queue()
        state.listeners.append(q)
        yield state.to_status()
        try:
            while True:
                if state.phase in (Phase.SUCCEEDED, Phase.FAILED, Phase.CANCELLED):
                    yield state.to_status()
                    return
                try:
                    status = await asyncio.wait_for(q.get(), timeout=1.0)
                    yield status
                    if status.phase in (Phase.SUCCEEDED, Phase.FAILED, Phase.CANCELLED):
                        return
                except asyncio.TimeoutError:
                    continue
        finally:
            try:
                state.listeners.remove(q)
            except ValueError:
                pass

    async def _notify(self, state: JobState) -> None:
        status = state.to_status()
        for q in list(state.listeners):
            await q.put(status)
