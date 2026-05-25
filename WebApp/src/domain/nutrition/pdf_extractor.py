"""Estrazione strutturata chunk-by-chunk via LLM in JSON mode."""

from __future__ import annotations

import json

from langchain_core.messages import SystemMessage, HumanMessage

from domain.nutrition.llm_client import build_extraction_llm
from domain.nutrition.pdf_chunker import Chunk


class AIExtractionError(Exception):
    """LLM ha fallito o ha restituito JSON invalido (su tutti i chunk)."""


CHUNK_SYSTEM_PROMPT = """Sei un estrattore di dati nutrizionali da PDF.
Ricevi un blocco di testo già filtrato da un documento PDF potenzialmente lungo.
Il tuo compito è estrarre SOLO dati utili per costruire una dieta strutturata.

REGOLE:
- Restituisci SOLO JSON valido, nessun testo fuori dal JSON
- Non inventare valori; se un valore non è presente usa null
- Se un valore è ambiguo imposta uncertain=true sul singolo food
- Normalizza i giorni in: MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY, SATURDAY, SUNDAY
- Normalizza i pasti in: BREAKFAST, MORNING_SNACK, LUNCH, AFTERNOON_SNACK, DINNER
- Normalizza le unità in: g, ml, portion, tbsp, tsp
- Estrai solo informazioni chiaramente legate a una dieta o a un pasto
- Ignora sezioni puramente descrittive, decorative o amministrative
- Dizionario sinonimi italiani (estesi e abbreviati, case-insensitive):
  Giorni estesi: lunedì→MONDAY, martedì→TUESDAY, mercoledì→WEDNESDAY,
                 giovedì→THURSDAY, venerdì→FRIDAY, sabato→SATURDAY, domenica→SUNDAY
  Giorni abbreviati (anche con punto): lun/lun.→MONDAY, mar/mar.→TUESDAY,
                 mer/mer.→WEDNESDAY, gio/gio.→THURSDAY, ven/ven.→FRIDAY,
                 sab/sab.→SATURDAY, dom/dom.→SUNDAY
  Giorni numerici: "giorno 1"/"1° giorno"→MONDAY, "giorno 2"→TUESDAY, ecc.
  Pasti: colazione→BREAKFAST, spuntino mattina/merenda mattina→MORNING_SNACK,
         pranzo→LUNCH, merenda/spuntino pomeriggio→AFTERNOON_SNACK, cena→DINNER
  Unità: gr/grammi→g, ml→ml, pz/porzione→portion, cucch/cucchiaio→tbsp, cucchiaino→tsp
  Nutrienti: kcal/calorie→calories, prot/proteine→protein_g, carb/CHO→carbs_g, fat/grassi/lipidi→fat_g

ALTERNATIVE / SOSTITUZIONI:
- Se un alimento è marcato come alternativa di un altro (testo: "alternativa", "in alternativa",
  "oppure", "o", "sostituibile con", "in sostituzione", elenco con bullet "alt:", "/" tra due cibi),
  inseriscilo come elemento dell'array "substitutions" dell'alimento PRINCIPALE — NON come food a sé.
- Per ogni alternativa cerca di intuire la modalità: "iso-kcal"/"isocalorica"→ISOKCAL,
  "iso-prot"/"isoproteica"→ISOPROT, "iso-carb"/"isoglucidica"→ISOCARB. Default ISOKCAL.

INTEGRATORI / SUPPLEMENTI:
- Se trovi sezioni con "integratore", "integratori", "supplementi", "integrazione",
  estrai gli item nell'array TOP-LEVEL "supplements" (NON dentro foods/meals).
- Per ogni integratore estrai: name, dose (es. "5 g", "1 cpr"), timing (es. "post-workout",
  "a colazione"), notes (opzionale).

RILEVAMENTO GIORNI — CRITICO:
- Estrai TUTTI i giorni esplicitamente menzionati nel chunk, ANCHE se il contenuto
  sembra ripetuto o vuoto. Non saltare un giorno solo perché il chunk è breve.
- Riconosci anche varianti: "Lun", "Lun.", "LUN", "lunedì", "LUNEDÌ", "Giorno 1",
  "1° giorno", "DAY 1" → MONDAY (e analoghi per gli altri).
- Se vedi un'intestazione tipo "Lun / Mar / Mer" senza contenuto sottostante,
  emetti comunque i giorni con meals=[] (servono come segnale di copertura).
- Non inventare giorni non presenti nel testo.

- Se il blocco non contiene dati nutrizionali utili, restituisci {"days": [], "supplements": []}

SCHEMA OUTPUT (parziale, sarà unito ad altri chunk):
{
  "days": [
    {
      "day_of_week": "MONDAY",
      "meals": [
        {
          "meal_type": "BREAKFAST",
          "foods": [
            {
              "name": "string",
              "quantity": float|null,
              "unit": "g"|"ml"|"portion"|"tbsp"|"tsp",
              "calories": float|null,
              "protein_g": float|null,
              "carbs_g": float|null,
              "fat_g": float|null,
              "uncertain": bool,
              "notes": string|null,
              "substitutions": [
                {
                  "name": "string",
                  "quantity": float|null,
                  "unit": "g"|"ml"|"portion"|"tbsp"|"tsp",
                  "mode": "ISOKCAL"|"ISOPROT"|"ISOCARB",
                  "uncertain": bool,
                  "notes": string|null
                }
              ]
            }
          ]
        }
      ]
    }
  ],
  "supplements": [
    {
      "name": "string",
      "dose": string|null,
      "timing": string|null,
      "notes": string|null,
      "uncertain": bool
    }
  ],
  "extraction_notes": string|null
}
"""


def extract_chunk(chunk: Chunk, llm=None) -> dict:
    """Chiama l'LLM su un singolo chunk. Ritorna dict (mai eccezione: errori → {})."""
    if llm is None:
        llm = build_extraction_llm(max_tokens=2000, timeout=30)

    user_msg = (
        f"Metadata chunk:\n"
        f"- page_number: {chunk.page_number}\n"
        f"- chunk_id: {chunk.chunk_id}\n"
        f"- page_type: {chunk.page_type}\n"
        f"- relevance_score: {chunk.relevance_score}\n\n"
        f"Testo del chunk:\n{chunk.text}\n\n"
        f"Restituisci SOLO JSON conforme allo schema."
    )
    try:
        resp = llm.invoke([
            SystemMessage(content=CHUNK_SYSTEM_PROMPT),
            HumanMessage(content=user_msg),
        ])
    except Exception as e:
        return {'days': [], 'extraction_notes': f'chunk {chunk.chunk_id} LLM error: {e}'}

    content = resp.content if isinstance(resp.content, str) else str(resp.content)
    try:
        raw = json.loads(content)
    except json.JSONDecodeError:
        return {'days': [], 'extraction_notes': f'chunk {chunk.chunk_id} JSON invalido'}

    # Annota provenienza su ogni food (per badge "Pag. N" nella revisione)
    for day in raw.get('days') or []:
        for meal in day.get('meals') or []:
            for food in meal.get('foods') or []:
                food.setdefault('source_page', chunk.page_number)
                food.setdefault('source_chunk', chunk.chunk_id)
                for sub in food.get('substitutions') or []:
                    sub.setdefault('source_page', chunk.page_number)
                    sub.setdefault('source_chunk', chunk.chunk_id)
    for supp in raw.get('supplements') or []:
        supp.setdefault('source_page', chunk.page_number)
    return raw


def extract_all_chunks(chunks: list[Chunk], progress_cb=None) -> tuple[list[dict], list[str]]:
    """Itera su tutti i chunk, ritorna (parts, notes). Solleva AIExtractionError
    solo se TUTTI i chunk falliscono.
    """
    llm = build_extraction_llm(max_tokens=2000, timeout=30)
    parts: list[dict] = []
    notes: list[str] = []
    n = len(chunks) or 1
    failed = 0
    for i, chunk in enumerate(chunks):
        result = extract_chunk(chunk, llm=llm)
        parts.append(result)
        extra_note = result.get('extraction_notes')
        if extra_note:
            notes.append(extra_note)
        if not (result.get('days') or []):
            failed += 1
        if progress_cb:
            try:
                progress_cb(i + 1, n)
            except Exception:
                pass
    if chunks and failed == len(chunks):
        raise AIExtractionError("Nessun chunk ha prodotto contenuto utile.")
    return parts, notes
