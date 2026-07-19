"""Modelli Pydantic per request/response CHIRON."""

from typing import Literal
from pydantic import BaseModel, Field

UserRole = Literal["coach", "allenatore", "nutrizionista", "utente"]
HistoryRole = Literal["user", "assistant"]


class HistoryMessage(BaseModel):
    role: HistoryRole
    content: str


class Source(BaseModel):
    """Un articolo peer-reviewed citato in risposta.

    I campi bibliografici sono opzionali perché Europe PMC non li espone per
    ogni record indicizzato; la UI mostra ciò che c'è.
    """
    title: str
    url: str
    authors: str | None = None
    year: int | None = None
    journal: str | None = None
    doi: str | None = None
    citations: int | None = None
    study_type: str | None = None


class Action(BaseModel):
    """Link/azione cliccabile dell'app, prodotto dai coach tool. Reso come pulsante."""
    label: str
    url: str


class ProposalField(BaseModel):
    """Un campo della proposta che il coach può correggere prima di confermare."""
    key: str
    label: str
    type: Literal["text", "textarea", "number", "date", "datetime-local", "select"] = "text"
    value: str | int | None = None
    options: list[dict] | None = None      # [{"value": ..., "label": ...}]
    help: str | None = None


class PendingAction(BaseModel):
    """Azione che MODIFICA i dati, proposta dal modello e in attesa di conferma del
    coach. NON eseguita finché il coach non conferma (pattern propose→confirm→execute).

    I parametri stanno in `payload`, non in campi fissi. La versione precedente
    dichiarava un campo per azione (`feedback`, `response_id`) e pydantic scartava
    silenziosamente tutto il resto: il testo scritto dal modello per `send_message`
    non arrivava mai al widget, che poi mostrava una textarea vuota. Con un dizionario
    aperto aggiungere un'azione non richiede di toccare lo schema, e `fields` descrive
    alla UI cosa rendere editabile.

    `payload` NON è fidato: `execute_action` ri-risolve tutto lato server.
    """
    action_type: str
    client_id: int
    title: str
    description: str
    payload: dict = Field(default_factory=dict)
    fields: list[ProposalField] = Field(default_factory=list)


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
