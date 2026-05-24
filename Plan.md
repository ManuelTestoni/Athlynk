# Nutrition Section Redesign — Design Spec

**Date:** 2026-05-24
**Author:** brainstorming session
**Status:** Draft for review
**Scope:** Coach / Nutritionist nutrition section (web app)
**Affected roles:** `COACH`, `NUTRITIONIST` (the `can_manage_nutrition` flag). Client-side nutrition views are untouched except where they depend on shared models.

---

## 1. Goal

Restructure the nutrition section so that it mirrors the workout section's information architecture: one hub page (Piani Alimentari) with folder taxonomy + filtered list + a multi-step wizard for plan creation. Move supplement management out of the sidebar and into a wizard step. Move Prima Visita out of the sidebar and into the hub header.

## 2. Out of Scope

- Client-facing nutrition pages (`client_piani.html`, `client_piano_detail.html`) — unchanged.
- Anamnesi (Prima Visita) internal flows — unchanged. Only entry point moves.
- Food taxonomy, food search API, PDF/Excel import internals — unchanged.
- Workout section — untouched.
- Notifications / email templates — unchanged (already trigger from `api_piano_assign`).

## 3. Sidebar Changes (`templates/base.html`)

### Remove
- Sub-menu expand block (currently lines ~160-180) containing:
  - `Piani Alimentari` link
  - `Prime Visite` link
  - `Integratori` link
- Nutritionist-only branch (lines ~218-225) loses no items but the nested expandable is removed.

### Keep / Replace
- A single top-level `Nutrizione` entry that links directly to `nutrizione_piani` (named URL). No expand toggle. No nested items.
- The badge dot (`sidebar_notifications.nutrizione`) stays.
- Permission gate `can_manage_nutrition` still gates visibility (no logic change).

### URL Routes (server-side)
- All existing `nutrizione_*` routes remain registered and reachable (URL deep-links keep working).
- `nutrizione_integratori` (list of supplement sheets) and `nutrizione_integratori_detail` remain accessible by URL only — useful for legacy sheets not yet linked to a plan, and for editing assignments standalone. No new sidebar entry.
- `nutrizione_anamnesi*` URLs remain reachable; entry point now lives as a button on the hub page (Section 4 below).

---

## 4. Hub Page — `pages/nutrizione/piani_list.html`

### 4.1 Header

```
[Eyebrow] Studio · Nutrizione
[H1]      Piani alimentari
[Body]    Organizza protocolli in cartelle e assegnali agli atleti.
[Rule bronze]
                                              [Prime Visite] [Nuovo piano]
```

- `Prime Visite`: `al-btn-ghost` with `ph ph-clipboard-text` icon. Click → navigate to `nutrizione_anamnesi`.
- `Nuovo piano`: `al-btn-bronze` with `ph ph-plus`. Click → open `newPlanModal` (Alpine state, see 4.4).
- Existing header buttons `Importa da Excel` / `Importa da PDF` are **removed** from the header. They migrate into the new-plan modal (Section 4.4).

### 4.2 Toolbar (new row, below header)

```
[🔍 Cerca piano…]      [Tutti(N)] [Attivi(N)] [Template(N)] [Bozza(N)]
```

- Left: search input `x-model="search"`. Filters `plans` client-side by `title`/`description` (case-insensitive, debounced 150 ms).
- Right: filter chips, mutually exclusive single-select. Counts derived live from the same dataset.
- Filter semantics (chip → predicate on a plan object):
  - `Tutti` → no predicate.
  - `Attivi` → `assigned_count > 0`.
  - `Template` → `is_template === true`.
  - `Bozza` → `status === 'DRAFT'`.
- Counts are recomputed any time `plans` mutates (delete / move folder / etc.). Counts are computed on the full dataset, NOT on the currently selected folder, so the user always sees the global state.
- Optional view toggle (grid/list) — keep only if `nutritionLibrary()` already exposes it; otherwise skip.

### 4.3 2-Column Shell

- Existing `wb-shell` / `wb-sidebar` / `wb-folder-list` (already mirrors the workout pattern). No structural change.
- Drag-and-drop of plans onto folders: keep existing endpoints (`api_nutrition_plan_folder`).
- Plan cards in the grid get a new badge: plan kind (`Giornaliero` / `Settimanale`), rendered next to the existing status badge. `kcal` shown is:
  - DAILY → sum of meal items (existing behaviour).
  - WEEKLY → average across compiled days (new derivation).

### 4.4 New-Plan Modal (Alpine, on `piani_list.html`)

State: `newPlanModal: false`, `newPlanKind: null` (`'DAILY' | 'WEEKLY'`).

Layout:
```
┌─ Nuovo piano alimentare                  [×] ─┐
│  al-rule-bronze                                │
│                                                │
│  Scegli tipo di piano                          │
│  ┌──────────────┐  ┌──────────────┐            │
│  │ ph-sun       │  │ ph-calendar  │            │
│  │ Giornaliero  │  │ Settimanale  │            │
│  │ "Un solo     │  │ "7 giorni    │            │
│  │  giorno,     │  │  con kcal    │            │
│  │  somma pasti"│  │  differenti  │            │
│  │              │  │  + media"    │            │
│  └──────────────┘  └──────────────┘            │
│                                                │
│  ─── oppure importa da file ───                │
│  [Excel] [PDF]   (al-btn-ghost-sm, small)      │
│                                                │
│             [Annulla]    [Continua →]          │
└────────────────────────────────────────────────┘
```

- Selecting a kind highlights the card (bronze outline, lift on hover, `is-selected` class).
- `Continua` is disabled until `newPlanKind` is set; click → navigate to `/nutrizione/piani/crea/?kind=DAILY` (or `WEEKLY`).
- `Excel` / `PDF` buttons navigate to existing `nutrizione_import` / `nutrizione_import_pdf` (no kind required — importer determines kind from imported content; if ambiguous, post-import landing decides).
- Escape key + overlay click close the modal.

---

## 5. Wizard — `/nutrizione/piani/crea/?kind=<DAILY|WEEKLY>`

Single-page Alpine wizard. Steps live in the same template; client-side step state plus URL query (`?step=info|builder|integratori|riepilogo`) for refresh-safety.

### 5.1 Header & Step Strip

- Breadcrumb: `Piani alimentari › Nuovo (Giornaliero|Settimanale)` (or `Modifica` in edit flow).
- Title: `Nuovo piano alimentare` + persistent non-editable badge showing kind.
- Step strip (sticky under header):
  ```
  ●─────○─────○─────○
  Info  Builder  Integratori  Riepilogo
  ```
- Step states:
  - **Active**: bronze filled circle, ink label.
  - **Completed**: bronze outlined circle with check.
  - **Future**: rule-grey circle.
- Click on a completed step → jump back (no validation needed).
- Click on a future step → blocked until prerequisites met (Info must be saved to unlock Builder, etc.).
- Top-right of wizard: `Salva bozza` (al-btn-ghost) + `Avanti →` (al-btn-bronze). `Avanti` becomes `Assegna` semantics on the final step (handled inside Step 4).

### 5.2 Step 1 — Informazioni

Fields:
- `Titolo *` (text)
- `Tipologia` (select: Ipocalorica / Normocalorica / Ipercalorica / Chetogenica / Vegana / Vegetariana — same options as today)
- `Obiettivo` (text)
- `Descrizione` (textarea)
- `Cartella` (select from coach's `NutritionFolder` list + `Senza cartella` option)
- Custom targets — 4 numeric inputs, all optional:
  - `kcal target`
  - `protein g target`
  - `carb g target`
  - `fat g target`
  - These populate the existing `NutritionPlan.{daily_kcal,protein_target_g,carb_target_g,fat_target_g}` fields and feed the builder's "Target personalizzato" widget.
- `Salva come modello riutilizzabile` (checkbox → `is_template`).

Behaviour on `Avanti`:
- Required: `Titolo` non-empty.
- `POST` to `nutrizione_piano_create` (existing) with `plan_kind` set from `?kind=`. Server creates `NutritionPlan` with `status='DRAFT'`.
- Response returns `plan_id`. Alpine state stores it; URL updates to `?kind=X&plan_id=N&step=builder` via `history.replaceState`.
- Subsequent step transitions PATCH the existing plan via `/api/nutrizione/piani/<id>/`.

### 5.3 Step 2 — Builder

See Section 6 (DAILY) and Section 7 (WEEKLY) for variant layouts. Common shell:

- Left: builder column (fluid width).
- Right (sticky, 320 px): info panel with three blocks:
  - **Totali giornalieri** — current-day totals. Kcal + 3 macros + progress bar vs target (if set in Step 1).
  - **Target personalizzato** — read-only mirror of Step 1 targets. If none set, shows muted hint "Nessun target impostato. Modifica in Informazioni."
  - **Pasti totali** — count of meals (for the currently viewed day in WEEKLY, or whole plan in DAILY).
- Bottom toolbar: `← Indietro` (returns to Info) + `Avanti →` (validates then goes to Integratori).

Validation before `Avanti`:
- DAILY: at least 1 `Meal` with at least 1 `MealItem`.
- WEEKLY: at least 1 `DietDay` with at least 1 `Meal` that has at least 1 `MealItem`.

### 5.4 Step 3 — Integrazione

Layout: single column with `[+ Aggiungi integratore]` button at top, inline rows below.

Each row:
- Supplement search (autocomplete via existing `api/nutrizione/integratori/`)
- `Dose` (text)
- `Timing` (text, e.g. "post-workout")
- `Note` (text)
- `×` to remove
- Drag handle to reorder

Below the list: `Note generali integrazione` (textarea) — saved on `SupplementSheet.notes`.

Bottom toolbar: `← Indietro` + `Salta` + `Avanti →`.

- `Salta` → go to Step 4 without creating a `SupplementSheet`.
- `Avanti` (with ≥1 item) → create or update `SupplementSheet` linked to the plan (see Section 8 model changes).
- If items are added then user goes back and clears them all before clicking `Avanti` → existing linked `SupplementSheet` is deleted and `plan.supplement_sheet` set to null.

### 5.5 Step 4 — Riepilogo & Assegna

Two-column layout (preview left, action panel right).

Preview (left):
- Plan badge (kind), title, type, goal, description.
- Macros block: 4 tiles with `value` + small `vs target` line; if delta exceeds ±10 % of target, color-code (red excess, amber deficit).
- Meals section:
  - DAILY: collapsed accordions, one per meal. Click expands food list with quantity (read-only).
  - WEEKLY: tabs (Lun…Dom + Media). Default tab: `Media`. Each tab shows same accordion layout as DAILY but for that day; `Media` shows aggregate read-only summary.
- Integration section: bullet list of supplements with dose + timing; if none, text `Nessun integratore`.

Action panel (right, sticky):
- `Salva bozza` (al-btn-ghost): PATCH `status='DRAFT'`. Redirect to `nutrizione_piani` with toast `Bozza salvata`.
- `Salva come template` (al-btn-ghost): PATCH `is_template=True, status='PUBLISHED'`. Redirect with toast `Template creato`.
- `Assegna ad atleti` (al-btn-bronze): open existing `_assign_modal.html` (multi-select clients + dates + notes). Confirm → PATCH `status='PUBLISHED'` + one `api_piano_assign` call per selected client. Redirect with toast `Piano assegnato a N atleti`.

Validation: all three actions require Step 1 (title) and Step 2 (at least one meal with one item) complete. If invalid, scroll to the missing step and highlight.

### 5.6 Auto-Save & Navigation Guard

- Field changes inside Builder (after the plan exists) PATCH to `/api/nutrizione/piani/<id>/` with debounce 300 ms.
- Meal CRUD uses dedicated endpoints (Section 9) — not bundled with full plan save.
- `beforeunload` listener fires only if there are pending unsaved edits (dirty flag). Avoids spurious prompts.

### 5.7 Edit Flow — `/nutrizione/piani/<id>/modifica/`

- Reuses the same template, prehydrated with the plan's data.
- Step strip starts on Step 1 with all four steps unlocked (since the plan already exists).
- `Avanti` on Step 4 behaviour:
  - If plan is `DRAFT` and not yet published → same as create flow (Assegna opens modal, etc.).
  - If plan is `PUBLISHED` → button label becomes `Aggiorna assegnazioni`, opens the assign modal pre-selecting current active clients; confirm replaces active assignments (existing `api_piano_assign` already cancels prior ACTIVE on assign).

---

## 6. Builder — DAILY Variant

### 6.1 Left Column

- Header row: `[+ Aggiungi pasto]` button (full-width, dashed, al-btn-ghost-bronze).
- Meal list — vertical, draggable handles (`⋮⋮`).

Each meal block:
```
┌─ Meal ─ ⋮⋮ ──────────────────────────────────┐
│ ① [Colazione_____] [08:00]      245 kcal     │
│ ─────────────────────────────────────────── │
│ • 80g  Avena               304 kcal · P:12 C:55 F:5
│ • 200ml Latte parz.         86 kcal · P:7 C:10 F:3
│ [🔍 Cerca alimento…]                          │
│ [×] remove                                    │
└───────────────────────────────────────────────┘
```

- Meal name editable inline (click).
- Time-of-day optional, time picker.
- Food search: existing `api_food_search`. On select, prompts quantity (g) via small popover.
- Removing a meal asks confirmation if it has ≥1 item.

### 6.2 Add-Meal Banner

Small Alpine modal (or inline expand) triggered by `[+ Aggiungi pasto]`:
```
┌─ Nuovo pasto                  [×] ─┐
│ Nome*: [___________]                │
│ Orario: [HH:MM] (opzionale)         │
│              [Annulla] [Crea]       │
└─────────────────────────────────────┘
```
- On Crea: `POST /api/nutrizione/piani/<id>/pasti/` with `name`, `time_of_day`, `day=null` for DAILY. Returns full meal object; appended to local state.

### 6.3 Right Panel

- **Totali giornalieri**: `sum(meal.items)` across all meals for kcal/protein/carb/fat. Each metric has a small progress bar vs target if Step 1 target is set; bar color reflects delta (within ±5 % bronze, within ±15 % amber, beyond red).
- **Target personalizzato**: as defined in Step 1.
- **Pasti totali**: `meals.length` plus a one-line breakdown `colazione · pranzo · cena · 2 spuntini`.

---

## 7. Builder — WEEKLY Variant

### 7.1 Day Tabs (Sticky)

Horizontal tab strip pinned under the step strip:
```
[Lun] [Mar] [Mer] [Gio] [Ven] [Sab] [Dom]    [📊 Media]
 ●     ○     ○     ○     ○     ○     ○
 1800  —     —     —     —     —     —    kcal
```

- 7 day tabs + 1 `Media` tab (chart icon).
- Sub-label per tab: kcal total for that day, or `—` if empty.
- Active tab: bronze underline + `bg-al-marble` cell.
- `Media` tab is disabled (muted, no click) until at least one day has ≥1 meal with ≥1 item.
- Tabs are scrollable on mobile, fully visible on desktop.

### 7.2 Day Tab Content

Same layout as DAILY (meal list + add-meal banner + food search). But:
- Each `Meal` is created with `day=<DietDay for the current weekday>`.
- A `DietDay` row is created lazily the first time the user adds a meal on a given weekday (`POST /api/nutrizione/piani/<id>/giorni/`).
- `Duplica da…` dropdown next to `[+ Aggiungi pasto]`:
  ```
  [⧉ Duplica da ▾]
    → Lun (3 pasti)
    → Mer (4 pasti)
    → …
  ```
  - Picking a source day clones all meals + items from that day into the current day. If current day already has meals, confirm dialog asks `Sostituisci o aggiungi?`.
  - Backed by `POST /api/nutrizione/piani/<id>/giorni/<dest_day>/copia-da/<src_day>/` with body `{mode: 'replace'|'append'}`.

### 7.3 Media Tab Content (Read-Only)

```
Media settimanale
──────────────────────────
kcal medi / giorno: 1850 (min 1700 · max 2000)
proteine medie:      120 g
carb medi:           210 g
grassi medi:          65 g

Breakdown per giorno
Lun  1800  P:115 C:200 F:70   [↗ vai]
Mar  1750  P:118 C:195 F:65   [↗ vai]
…
Dom  —    (vuoto)
```

- Mean is arithmetic, computed only over *non-empty* days. Empty days surface as `vuoto` rows but do not contribute to the mean. The header line shows the count of days included (e.g. `media su 5 giorni compilati`).
- Click on a day row jumps to that day's tab.

### 7.4 Right Panel — WEEKLY

- **Totali giornalieri**: when a day tab is active → totals for that day. When `Media` tab is active → labelled `Media settimanale` and shows mean values; progress bar vs target stays (per-day target is the meaningful comparison for both).
- **Target personalizzato**: same as DAILY, always shows Step 1 targets (per-day semantics).
- **Pasti totali**: meals for the selected day, or `media: X.X pasti/giorno` on the Media tab.

---

## 8. Data-Model Changes

### 8.1 `NutritionPlan` (new fields)

```python
PLAN_KIND_CHOICES = [('DAILY', 'Giornaliero'), ('WEEKLY', 'Settimanale')]
plan_kind = models.CharField(max_length=10, choices=PLAN_KIND_CHOICES, default='DAILY')
supplement_sheet = models.OneToOneField(
    SupplementSheet, null=True, blank=True,
    on_delete=models.SET_NULL, related_name='nutrition_plan',
)
```

- Migration `0007_nutritionplan_kind_supplement.py`.
- Default for existing rows: `plan_kind='DAILY'` (preserves current single-day semantics). Existing rows that have any `DietDay` children → backfill set to `WEEKLY` in a data-migration step.
- `supplement_sheet` is null for plans without an integration step. Deleting the plan should `CASCADE` delete the linked sheet only if the sheet is solely tied to that plan; safest approach is to delete via app logic in `nutrizione_piano_delete_view` (not via DB cascade) so legacy sheets keep working.

### 8.2 `DietDay` (no field changes)

- Already has `day_of_week` choices and `unique_together('plan', 'day_of_week')`. Reused for WEEKLY plans.
- DAILY plans have zero `DietDay` rows; `Meal.day` is null.

### 8.3 `Meal` (no field changes)

- Already has nullable `day` FK. WEEKLY plans set it; DAILY plans leave null.

### 8.4 `SupplementSheet` (no field changes)

- Continues to support standalone sheets (sheets not linked to any plan), for legacy detail/edit URLs.

---

## 9. API Endpoints

### 9.1 Existing — Keep As-Is

- `GET /api/nutrizione/alimenti/` (food search)
- `POST /api/nutrizione/import/excel|pdf/` (imports)
- `POST /api/nutrizione/piani/<id>/assegna/` (`api_piano_assign`)
- `POST /api/nutrizione/piani/<id>/elimina/`
- `GET /api/nutrizione/cartelle/`, `POST/PATCH/DELETE /api/nutrizione/cartelle/<id>/`
- `PATCH /api/nutrizione/piani/<id>/cartella/`
- `GET /api/nutrizione/integratori/` (supplement search)

### 9.2 Existing — Extend

- `POST /nutrizione/piani/crea/` (`nutrizione_piano_create_view`) — accept new `plan_kind` in payload, default `DAILY`. Return JSON `{plan_id, ...}` for the wizard.
- `POST /nutrizione/piani/<id>/modifica/` (`nutrizione_piano_edit_view`) — accept `plan_kind` (read-only after creation; reject changes if it would break existing meal/day topology).
- `POST /api/nutrizione/piani/<id>/assegna/` (`api_piano_assign`) — no signature change, but caller can now invoke from Step 4 of the wizard.

### 9.3 New

| Method | Path | Purpose |
|--------|------|---------|
| `PATCH` | `/api/nutrizione/piani/<id>/` | Partial update of a plan (title, description, targets, status, is_template). Used for auto-save and final transitions. |
| `POST` | `/api/nutrizione/piani/<id>/pasti/` | Create a meal. Body `{name, time_of_day?, day_of_week?}`. For DAILY plans, `day_of_week` is ignored. For WEEKLY plans, `day_of_week` is required; server creates the `DietDay` lazily if missing. |
| `PATCH` | `/api/nutrizione/pasti/<meal_id>/` | Update meal name / time / order. |
| `DELETE` | `/api/nutrizione/pasti/<meal_id>/` | Delete meal (and its items via cascade). |
| `POST` | `/api/nutrizione/pasti/<meal_id>/alimenti/` | Add a food item to a meal. Body `{food_id, quantity_g, notes?}`. |
| `PATCH` | `/api/nutrizione/alimenti/<item_id>/` | Update quantity / notes. |
| `DELETE` | `/api/nutrizione/alimenti/<item_id>/` | Remove a food item. |
| `POST` | `/api/nutrizione/piani/<id>/giorni/<dest_day>/copia-da/<src_day>/` | Clone all meals+items from `src_day` into `dest_day`. Body `{mode: 'replace'\|'append'}`. WEEKLY only. |
| `PUT` | `/api/nutrizione/piani/<id>/integratori/` | Create or update the `SupplementSheet` linked to the plan. Body `{items: [{supplement_id, dose, timing, notes}], notes: ''}`. Pass empty `items` to delete the linked sheet. |

All endpoints are coach-only (existing `get_session_coach` guard), respond JSON, accept `application/json`, and use the CSRF cookie via `nutCsrfToken()` helper already in `piani_list.html`.

---

## 10. Frontend Code Structure

### 10.1 Templates (new + modified)

| File | Action | Notes |
|------|--------|-------|
| `templates/base.html` | Modify | Remove nutrition sub-menu; flatten to single link. |
| `templates/pages/nutrizione/piani_list.html` | Modify | Add toolbar (search + filters), Prima Visite header button, new-plan modal. Remove import buttons from header. |
| `templates/pages/nutrizione/piano_create.html` | Replace | New 4-step wizard shell. Same template handles create + edit. |
| `templates/pages/nutrizione/_wizard_step_info.html` | New (partial) | Step 1 form fields. |
| `templates/pages/nutrizione/_wizard_step_builder_daily.html` | New (partial) | Daily meal list. |
| `templates/pages/nutrizione/_wizard_step_builder_weekly.html` | New (partial) | Weekly day tabs + meal list. |
| `templates/pages/nutrizione/_wizard_step_integratori.html` | New (partial) | Supplement list. |
| `templates/pages/nutrizione/_wizard_step_riepilogo.html` | New (partial) | Final preview + 3 action buttons. |
| `templates/pages/nutrizione/_wizard_side_panel.html` | New (partial) | Right-hand totals panel. |
| `templates/pages/nutrizione/_assign_modal.html` | Keep | Reused as-is by Step 4. |
| `templates/pages/nutrizione/integratori_*.html` | Keep | Reachable by URL only (legacy edit/detail). |

### 10.2 JS (new + modified)

| File | Action | Notes |
|------|--------|-------|
| `static/js/nutrition_library.js` | New | Extract `nutritionLibrary()` from `piani_list.html` (currently inline at line 381). Add `newPlanModal`, `search`, `activeFilter`, `filterCounts` getters. |
| `static/js/nutrition_wizard.js` | New | Main `nutritionWizard()` Alpine component. Handles step state, validation, autosave, navigation. ≈400-600 LOC. |
| `static/js/nutrition_wizard_builder_daily.js` | New | Helper sub-component for DAILY meal management. |
| `static/js/nutrition_wizard_builder_weekly.js` | New | Helper sub-component for WEEKLY day tabs + duplication. |
| `static/js/diet_importer.js` | Keep | Unchanged — invoked from the import buttons inside the new-plan modal. |
| `static/js/diet_importer_pdf_config.js` | Keep | Unchanged. |

Rationale for splitting JS: the existing `workout_wizard.js` (2486 LOC) demonstrates that a monolithic wizard quickly outgrows comprehension. Splitting per-step and per-variant keeps each file under ~500 LOC and isolates DAILY vs WEEKLY logic.

### 10.3 Views (Python)

| File | Action | Notes |
|------|--------|-------|
| `src/config/views_nutrition.py` | Modify | Extend create/edit views with `plan_kind` handling. Add new endpoints (Section 9.3). |
| `src/config/urls.py` | Modify | Register new endpoint routes. |
| `src/domain/nutrition/models.py` | Modify | Add `plan_kind`, `supplement_sheet`. |
| `src/domain/nutrition/migrations/0007_*.py` | New | Schema migration + data migration for `plan_kind` backfill. |

---

## 11. Aesthetic & Design Tokens

The redesign stays within the existing **Athlynk** design system (parchment background, bronze accent, ink text, marble surfaces). No new theme. No new fonts. New visual elements use existing tokens:

- `al-card`, `al-card-warm`, `al-card-flush` for surfaces.
- `al-btn-bronze`, `al-btn-ghost`, `al-btn-icon` for buttons. New small variant `al-btn-ghost-sm` may be needed for the modal's import buttons (or reuse existing `al-btn-icon` with a label).
- `al-tag` for badges (plan kind, status).
- `al-eyebrow`, `al-h-1`, `al-h-3`, `al-body`, `al-label` for typography.
- Icons exclusively from Phosphor (`ph ph-*` and `ph-fill`).
- Bronze rule (`al-rule-bronze`) under section headers.
- Step strip uses bronze for active/completed states, `var(--al-rule)` for future steps.
- Filter chips: existing `al-tag` plus an `is-active` variant with bronze background.

The only new layout element is the **horizontal day tab strip** for WEEKLY. It uses `border-bottom: 2px solid bronze` for active state and `text-ink-mute` for inactive — consistent with existing tab patterns in `templates/pages/allenamenti/wizard.html`.

---

## 12. Edge Cases & Error Handling

- **User navigates away mid-wizard**: `beforeunload` prompt only fires if there are unsaved (debounced) edits. After auto-save settles, prompt disappears.
- **Plan_kind change**: not supported after creation. The wizard hides any kind-switch UI in edit mode. Server validates on `PATCH` and returns 400 if `plan_kind` differs from stored value.
- **WEEKLY plan with zero compiled days**: `Media` tab disabled; validation blocks Avanti from Step 2. Toast: `Compila almeno un giorno prima di continuare.`
- **DAILY plan with zero meals**: same validation pattern.
- **Duplicating a day onto a non-empty day**: confirm dialog `Sostituisci o aggiungi?`. `Sostituisci` = wipe existing meals on dest day then clone; `Aggiungi` = append clones with `order` shifted.
- **Deleting a plan that owns a `SupplementSheet`**: in `nutrizione_piano_delete_view`, delete the linked sheet only if it has no `SupplementAssignment` rows. Otherwise unlink (`plan.supplement_sheet = None`) and keep the sheet alive so existing assignments remain functional.
- **Concurrent edits to the same plan from two tabs**: out of scope. Last-write-wins via auto-save.
- **Permission**: every wizard URL and API endpoint is gated by `can_manage_nutrition` (existing guard). A client hitting `/piani/crea/` is redirected to dashboard.
- **Existing import flow** (`import_diet.html`, `import_diet_pdf.html`): import completion currently lands on `piano_create.html` (edit-mode for the newly created plan). After this redesign, it lands on the wizard at Step 1, with all fields prepopulated and `plan_kind` inferred from the imported structure (single-day → DAILY, multi-day → WEEKLY).

---

## 13. Testing Notes

- **Migrations**: ensure `0007` is idempotent on dev DBs that may already have hand-crafted plans. Backfill rule: any plan with `DietDay` children → `WEEKLY`, else `DAILY`.
- **Wizard navigation**: each step transition should be exercised both forward (Avanti) and backward (step-strip click).
- **Auto-save**: simulate slow network; ensure debounce does not duplicate PATCHes and that dirty flag clears on success.
- **Filter counts**: verify counts react to delete / assign / template-toggle without page reload.
- **Importer landing**: both Excel and PDF imports should produce a wizard-compatible plan (correct `plan_kind`, meals attached to days for WEEKLY).
- **Permission tests**: client accounts must be redirected away from `/piani/crea/`.

---

## 14. Open Questions (to resolve before plan)

None at design time — all major UX decisions were made in brainstorming. Implementation plan can begin.

---

## 15. File Manifest Summary

**New files (12):**
- `templates/pages/nutrizione/_wizard_step_info.html`
- `templates/pages/nutrizione/_wizard_step_builder_daily.html`
- `templates/pages/nutrizione/_wizard_step_builder_weekly.html`
- `templates/pages/nutrizione/_wizard_step_integratori.html`
- `templates/pages/nutrizione/_wizard_step_riepilogo.html`
- `templates/pages/nutrizione/_wizard_side_panel.html`
- `static/js/nutrition_library.js`
- `static/js/nutrition_wizard.js`
- `static/js/nutrition_wizard_builder_daily.js`
- `static/js/nutrition_wizard_builder_weekly.js`
- `src/domain/nutrition/migrations/0007_nutritionplan_kind_supplement.py`
- `docs/superpowers/specs/2026-05-24-nutrition-section-redesign-design.md` (this file)

**Modified files (6):**
- `templates/base.html` (sidebar simplification)
- `templates/pages/nutrizione/piani_list.html` (toolbar + modal + button migration)
- `templates/pages/nutrizione/piano_create.html` (full rewrite as wizard shell)
- `src/config/views_nutrition.py` (new endpoints, plan_kind handling)
- `src/config/urls.py` (new endpoint routes)
- `src/domain/nutrition/models.py` (new fields on `NutritionPlan`)