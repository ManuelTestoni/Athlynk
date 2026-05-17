"""Modelli Pydantic per request/response CHIRON."""

from typing import Literal
from pydantic import BaseModel, Field

UserRole = Literal["coach", "allenatore", "nutrizionista", "utente"]
HistoryRole = Literal["user", "assistant"]


class HistoryMessage(BaseModel):
    role: HistoryRole
    content: str


class Source(BaseModel):
    title: str
    url: str


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=4000)
    user_role: UserRole
    conversation_history: list[HistoryMessage] = Field(default_factory=list)


class ChatResponse(BaseModel):
    response: str
    sources: list[Source] = Field(default_factory=list)
    used_web_search: bool = False
