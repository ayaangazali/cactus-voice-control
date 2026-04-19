import asyncio
from uuid import uuid4

import pytest

from cactus_voice_mac.models import CommandIntent, Phase
from cactus_voice_mac.runner import Runner


def make_intent(instruction: str = "Open Notes and write hello") -> CommandIntent:
    return CommandIntent.model_validate(
        {
            "id": str(uuid4()),
            "instruction": instruction,
            "output_description": None,
            "urgency": "normal",
            "raw_transcript": "say something",
            "model_id": "qwen3",
        }
    )


def test_build_argv_minimal():
    r = Runner(mobile_use_cmd="echo")
    argv = r.build_argv(make_intent("hello world"))
    assert argv[0] == "echo"
    assert "hello world" in argv


def test_build_argv_with_output_description():
    r = Runner(mobile_use_cmd="echo")
    intent = CommandIntent.model_validate(
        {
            "id": str(uuid4()),
            "instruction": "list emails",
            "output_description": "JSON list",
            "urgency": "normal",
            "raw_transcript": "x",
            "model_id": "qwen3",
        }
    )
    argv = r.build_argv(intent)
    assert "--output-description" in argv
    assert "JSON list" in argv


def test_build_argv_with_udid():
    r = Runner(mobile_use_cmd="echo", target_udid="ABC-123")
    argv = r.build_argv(make_intent())
    assert "--device" in argv
    assert "ABC-123" in argv


def test_build_argv_splits_compound_command():
    r = Runner(mobile_use_cmd="uv run mobile-use")
    argv = r.build_argv(make_intent("x"))
    assert argv[:3] == ["uv", "run", "mobile-use"]
    assert "x" in argv


@pytest.mark.asyncio
async def test_run_echo_succeeds():
    r = Runner(mobile_use_cmd="echo")
    intent = make_intent("hello")
    state = await r.start(intent)
    assert state.phase in {Phase.RUNNING, Phase.SUCCEEDED}
    for _ in range(50):
        if state.phase in {Phase.SUCCEEDED, Phase.FAILED}:
            break
        await asyncio.sleep(0.05)
    assert state.phase == Phase.SUCCEEDED
    assert state.result is not None and "hello" in state.result


@pytest.mark.asyncio
async def test_missing_binary_fails():
    r = Runner(mobile_use_cmd="this-binary-does-not-exist-xyz")
    state = await r.start(make_intent())
    assert state.phase == Phase.FAILED
    assert state.message and "not found" in state.message.lower()


@pytest.mark.asyncio
async def test_subscribe_yields_terminal_status():
    r = Runner(mobile_use_cmd="echo")
    intent = make_intent("subscribed")
    await r.start(intent)
    seen: list[Phase] = []
    async for status in r.subscribe(intent.id):
        seen.append(status.phase)
        if status.phase in {Phase.SUCCEEDED, Phase.FAILED, Phase.CANCELLED}:
            break
    assert seen[-1] in {Phase.SUCCEEDED, Phase.FAILED}
