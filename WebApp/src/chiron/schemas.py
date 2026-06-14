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


class Action(BaseModel):
    """Link/azione cliccabile dell'app, prodotto dai coach tool. Reso come pulsante."""
    label: str
    url: str


class PendingAction(BaseModel):
    """Azione che MODIFICA i dati, proposta dal modello e in attesa di conferma del
    coach. NON eseguita finché il coach non conferma (pattern propose→confirm→execute)."""
    action_type: str
    client_id: int
    response_id: int | None = None
    feedback: str | None = None
    editable_field: str | None = None
    title: str
    description: str


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=4000)
    user_role: UserRole
    conversation_history: list[HistoryMessage] = Field(default_factory=list)


class ChatResponse(BaseModel):
    response: str
    sources: list[Source] = Field(default_factory=list)
    used_web_search: bool = False
    actions: list[Action] = Field(default_factory=list)
    pending_action: PendingAction | None = None
