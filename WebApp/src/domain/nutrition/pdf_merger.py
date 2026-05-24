"""Merge dei risultati parziali (chunk-level) in una DietExtraction unica.

Strategia:
- raggruppa per (day_of_week, meal_type)
- dedup food per name normalizzato all'interno dello stesso meal
- preserva source_page/source_chunk del primo match
- ordina giorni per ordine settimanale standard e pasti per ordine pasto standard
"""

from __future__ import annotations

import re

DAY_ORDER = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY']
MEAL_ORDER = ['BREAKFAST', 'MORNING_SNACK', 'LUNCH', 'AFTERNOON_SNACK', 'DINNER']

_VALID_DAYS = set(DAY_ORDER)
_VALID_MEALS = set(MEAL_ORDER)


def _norm_name(s: str) -> str:
    s = (s or '').strip().lower()
    s = re.sub(r'\s+', ' ', s)
    return s


def merge_chunks(parts: list[dict], document_summary: dict | None = None,
                 extra_notes: list[str] | None = None,
                 diet_name: str | None = None) -> dict:
    """Costruisce un dict compatibile con DietExtraction (pydantic)."""
    # day_of_week → meal_type → {meal_dict, foods_by_name}
    days_map: dict[str, dict[str, dict]] = {}

    for part in parts or []:
        for day in (part.get('days') or []):
            dow = day.get('day_of_week')
            if dow not in _VALID_DAYS:
                continue
            day_bucket = days_map.setdefault(dow, {})
            for meal in (day.get('meals') or []):
                mt = meal.get('meal_type')
                if mt not in _VALID_MEALS:
                    continue
                meal_bucket = day_bucket.setdefault(mt, {
                    'meal_type': mt,
                    'foods': [],
                    '_foods_by_name': {},
                })
                for food in (meal.get('foods') or []):
                    name = (food.get('name') or '').strip()
                    if not name:
                        continue
                    key = _norm_name(name)
                    if key in meal_bucket['_foods_by_name']:
                        # già presente: propaga uncertain se diverso
                        existing = meal_bucket['_foods_by_name'][key]
                        if food.get('uncertain') and not existing.get('uncertain'):
                            existing['uncertain'] = True
                        continue
                    food_norm = {
                        'name': name,
                        'quantity': food.get('quantity'),
                        'unit': food.get('unit') or 'g',
                        'calories': food.get('calories'),
                        'protein_g': food.get('protein_g'),
                        'carbs_g': food.get('carbs_g'),
                        'fat_g': food.get('fat_g'),
                        'uncertain': bool(food.get('uncertain', False)),
                        'notes': food.get('notes'),
                        'source_page': food.get('source_page'),
                        'source_chunk': food.get('source_chunk'),
                    }
                    meal_bucket['_foods_by_name'][key] = food_norm
                    meal_bucket['foods'].append(food_norm)

    # Build ordered output
    days_out = []
    for dow in DAY_ORDER:
        if dow not in days_map:
            continue
        meals_bucket = days_map[dow]
        meals_out = []
        for mt in MEAL_ORDER:
            if mt not in meals_bucket:
                continue
            m = meals_bucket[mt]
            m.pop('_foods_by_name', None)
            meals_out.append(m)
        days_out.append({'day_of_week': dow, 'meals': meals_out})

    # Notes
    notes_collected: list[str] = []
    for part in parts or []:
        en = part.get('extraction_notes')
        if isinstance(en, str) and en.strip():
            notes_collected.append(en.strip())
    if extra_notes:
        notes_collected.extend([n for n in extra_notes if n])
    notes_str = ' | '.join(notes_collected) if notes_collected else None

    out = {
        'diet_name': diet_name or None,
        'days': days_out,
        'extraction_notes': notes_str,
        'total_calories_daily': None,
        'notes': None,
    }
    if document_summary:
        out['document_summary'] = document_summary
    return out
