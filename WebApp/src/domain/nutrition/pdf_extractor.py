"""Estrazione strutturata chunk-by-chunk via LLM in JSON mode."""

from __future__ import annotations

import json

from langchain_core.messages import SystemMessage, HumanMessage

from domain.nutrition.llm_client import build_extraction_llm
from domain.shared.extraction import AIExtractionError  # noqa: F401  (re-export)
from domain.shared.pdf import Chunk


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
        llm = build_extraction_llm(max_tokens=4000, timeout=45)

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


RETRY_EMPTY_RELEVANCE_THRESHOLD = 0.5
RETRY_SYSTEM_SUFFIX = (
    "\n\nRETRY ESAUSTIVO: la passata precedente non ha estratto alimenti da "
    "questo chunk nonostante sia rilevante. Sii MASSIMAMENTE esaustivo: scorri "
    "il testo riga per riga, estrai OGNI alimento, quantità o pasto presente. "
    "Non saltare elementi perché ripetitivi. Se il chunk contiene anche solo "
    "un'intestazione di giorno/pasto, emetti la struttura corrispondente."
)


def extract_all_chunks(chunks: list[Chunk], progress_cb=None) -> tuple[list[dict], list[str]]:
    """Itera su tutti i chunk, ritorna (parts, notes). Solleva AIExtractionError
    solo se TUTTI i chunk falliscono.

    Due passate:
      1. Prima passata standard
      2. Retry mirato sui chunk ad alta rilevanza che hanno restituito 0 giorni
         (probabile truncation o "laziness" LLM)
    """
    llm = build_extraction_llm(max_tokens=4000, timeout=45)
    parts: list[dict] = []
    notes: list[str] = []
    n = len(chunks) or 1
    failed = 0
    # Track per chunk_id se la prima passata ha prodotto qualcosa
    empty_high_relevance: list[Chunk] = []

    for i, chunk in enumerate(chunks):
        result = extract_chunk(chunk, llm=llm)
        parts.append(result)
        extra_note = result.get('extraction_notes')
        if extra_note:
            notes.append(extra_note)
        produced_days = bool(result.get('days') or [])
        produced_supps = bool(result.get('supplements') or [])
        if not produced_days:
            failed += 1
        if (not produced_days and not produced_supps
                and chunk.relevance_score >= RETRY_EMPTY_RELEVANCE_THRESHOLD):
            empty_high_relevance.append(chunk)
        if progress_cb:
            try:
                # prima passata occupa l'80% del progress; il 20% restante è retry
                progress_cb(i + 1, n + max(1, len(empty_high_relevance)))
            except Exception:
                pass

    # Passata 2 — retry chunk ad alta rilevanza rimasti vuoti
    if empty_high_relevance:
        retry_llm = build_extraction_llm(max_tokens=4000, timeout=60)
        for j, chunk in enumerate(empty_high_relevance):
            retry_result = _extract_chunk_with_suffix(chunk, retry_llm, RETRY_SYSTEM_SUFFIX)
            if retry_result.get('days') or retry_result.get('supplements'):
                parts.append(retry_result)
                notes.append(f'retry chunk {chunk.chunk_id}: recuperato')
            elif retry_result.get('extraction_notes'):
                notes.append(retry_result['extraction_notes'])
            if progress_cb:
                try:
                    progress_cb(n + j + 1, n + len(empty_high_relevance))
                except Exception:
                    pass

    if chunks and failed == len(chunks):
        # Considera anche eventuali recuperi dal retry
        if not any((p.get('days') or p.get('supplements')) for p in parts):
            raise AIExtractionError("Nessun chunk ha prodotto contenuto utile.")
    return parts, notes


def _extract_chunk_with_suffix(chunk: Chunk, llm, suffix: str) -> dict:
    """Variante di extract_chunk con suffisso al system prompt (per retry)."""
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
            SystemMessage(content=CHUNK_SYSTEM_PROMPT + suffix),
            HumanMessage(content=user_msg),
        ])
    except Exception as e:
        return {'days': [], 'extraction_notes': f'retry chunk {chunk.chunk_id} LLM error: {e}'}

    content = resp.content if isinstance(resp.content, str) else str(resp.content)
    try:
        raw = json.loads(content)
    except json.JSONDecodeError:
        return {'days': [], 'extraction_notes': f'retry chunk {chunk.chunk_id} JSON invalido'}

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
