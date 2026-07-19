"""System prompts for workout extraction (Excel sync + PDF chunk-by-chunk)."""

SHARED_JSON_SCHEMA_HINT = """
SCHEMA OUTPUT richiesto (JSON, nessun testo fuori dal JSON):
{
  "plan_name": string | null,
  "frequency_per_week": int | null,
  "goal": string | null,
  "notes": string | null,
  "sessions": [
    {
      "day_label": string,
      "day_of_week": "MONDAY"|"TUESDAY"|"WEDNESDAY"|"THURSDAY"|"FRIDAY"|"SATURDAY"|"SUNDAY"|null,
      "session_type": string | null,
      "order_index": int,
      "notes": string | null,
      "blocks": [
        {
          "block_name": string | null,
          "block_type": "straight"|"superset"|"circuit"|"emom"|"amrap"|null,
          "exercises": [
            {
              "raw_name": string,
              "name_en": string | null,
              "sets": int | null,
              "reps": int | string | null,
              "reps_type": "fixed"|"range"|"amrap"|"time"|"distance"|null,
              "load": float | null,
              "load_unit": "kg"|"lb"|"bw"|"band"|null,
              "load_type": "absolute"|"percentage_1rm"|"rpe"|null,
              "rpe": float | null,
              "rir": int | null,
              "tempo": string | null,
              "rest_seconds": int | null,
              "rest_label": string | null,
              "distance": float | null,
              "distance_unit": "m"|"km"|"mi"|null,
              "duration_seconds": int | null,
              "notes": string | null,
              "uncertain": bool
            }
          ]
        }
      ]
    }
  ],
  "extraction_notes": [string]
}
"""

EXCEL_SYSTEM_PROMPT = """Sei un estrattore di schede di allenamento. Ricevi il contenuto grezzo di un
file Excel creato da un personal trainer / coach e devi mapparlo nello schema JSON standard.

REGOLE:
- Restituisci SOLO JSON valido, nessun testo fuori dal JSON
- Per i campi non trovati usa null, MAI inventare dati
- Normalizza i giorni in inglese maiuscolo: MONDAY..SUNDAY (anche se nel doc compaiono "Lunedì", "Lun", "Day 1", "A", "Push")
- Mantieni il `day_label` originale (es. "Push", "Lunedì", "Giorno A")
- Riconosci sessioni nominate (Push/Pull/Legs/Upper/Lower/Full Body/Cardio) in `session_type`
- Blocchi: gruppi di esercizi marcati come "Superset A1/A2", "Circuit", "A/B/C": usa `block_type` corretto e `block_name`
- Se gli esercizi sono in elenco lineare, raggruppali in UN blocco con `block_type="straight"`
- Sets/reps: "4x8" → sets=4, reps=8, reps_type=fixed. "3x6-8" → sets=3, reps="6-8", reps_type=range.
  "AMRAP" → reps_type=amrap. "30s"/"20 sec" → reps_type=time, duration_seconds dell'esercizio.
- Carico: "80kg" → load=80, load_unit=kg, load_type=absolute. "70%" → load=70, load_unit=null, load_type=percentage_1rm.
  "bodyweight"/"BW"/"corpo libero" → load_unit=bw. RPE/RIR sono campi separati, non confonderli col load.
- Recupero: "90s"/"1'30"/"2 min" → rest_seconds calcolato; mantieni anche `rest_label` testuale.
  "a piacere"/"libero" → rest_label="a piacere", rest_seconds=null.
- Tempo: "3010"/"3-0-1-0"/"X010" → tempo (string esatta)
- Note tecniche dell'esercizio → field `notes`
- Per esercizi ambigui o con dati mancanti aggiungi "uncertain": true
- Goal: se nel documento ci sono indicazioni tipo "ipertrofia", "forza", "definizione" → goal
- frequency_per_week: numero di sessioni distinte rilevate, se il doc lo esplicita altrove usa quello

`raw_name`: SEMPRE la formulazione originale del documento, verbatim, MAI tradotta.

`name_en`: la stessa cosa resa in inglese, con la nomenclatura standard da palestra
(es. "Panca piana con bilanciere" → "barbell bench press"; "Rematore con bilanciere" →
"barbell bent over row"; "Pressa 45 gradi" → "45 degrees leg press"; "Alzate laterali con
manubri" → "dumbbell lateral raise"). Serve a ritrovare l'esercizio nel database, che è in
inglese. REGOLE:
- includi SEMPRE l'attrezzo se il documento lo indica (bilanciere→barbell, manubri→dumbbell,
  cavi→cable, macchina→machine/lever, elastico→band, corpo libero→bodyweight)
- mantieni le varianti che cambiano il movimento (inclinata→incline, presa stretta→close grip,
  sdraiato→lying, in piedi→standing, monoarto→single arm)
- se il nome è già in inglese, ripetilo identico
- se non sai tradurre, usa null (meglio null di una traduzione inventata)

""" + SHARED_JSON_SCHEMA_HINT


CHUNK_SYSTEM_PROMPT = """Sei un estrattore di schede di allenamento da chunk di testo PDF. Per ogni
chunk restituisci SOLO il JSON delle sessioni/blocchi/esercizi presenti nel chunk
(parziale ammesso: chunk diversi verranno uniti dopo).

REGOLE:
- Restituisci SOLO JSON valido conforme allo schema, nessun testo fuori
- Per ogni esercizio includi `source_page` (1-indexed) e `source_chunk` (lascia null,
  saranno reiniettati dall'orchestratore)
- Per campi non trovati usa null, MAI inventare dati
- Riconosci day_label e blocchi come specificato (Push/Pull/Legs, A/B, Superset, Circuit)
- Se il chunk contiene solo metadati (intestazione, goal) restituisci `sessions: []`
  ma popola plan_name/goal/frequency_per_week/notes se rilevati
- Se il chunk contiene SOLO uno spezzone di sessione, restituisci comunque la sessione
  parziale: il merger unirà con altri chunk
- Sets/reps/load/rpe/rir/rest_seconds/tempo come da schema; NON sommare set tra chunk
- uncertain=true se nome esercizio è ambiguo o dati mancanti
- extraction_notes: lista di warning testuali (es. "Pagina con tabella distorta")

""" + SHARED_JSON_SCHEMA_HINT
