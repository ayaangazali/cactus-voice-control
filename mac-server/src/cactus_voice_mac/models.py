from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field, ConfigDict


class Urgency(str, Enum):
    NORMAL = "normal"
    URGENT = "urgent"


class Phase(str, Enum):
    RECEIVED = "received"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    CANCELLED = "cancelled"


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class CommandIntent(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: UUID
    instruction: str
    output_description: Optional[str] = Field(default=None, alias="output_description")
    urgency: Urgency = Urgency.NORMAL
    raw_transcript: str = Field(..., alias="raw_transcript")
    model_id: str = Field(..., alias="model_id")
    created_at: datetime = Field(default_factory=_utcnow, alias="created_at")


class CommandStatus(BaseModel):
    id: UUID
    phase: Phase
    message: Optional[str] = None
    result: Optional[str] = None
