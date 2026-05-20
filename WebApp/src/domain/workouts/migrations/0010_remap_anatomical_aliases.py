"""Second pass over Exercise.primary/secondary/target_muscle_group with an
expanded alias table that covers the anatomical-Italian terminology used in
the seed catalog (e.g. "grande pettorale", "deltoidi anteriori", "femorale",
"retto dell'addome").
"""

from __future__ import annotations

import re
import unicodedata

from django.db import migrations


# Anatomical → muscle slug. Lowercase, accent-stripped.
ANATOMICAL_ALIASES = {
    # CHEST
    'grande pettorale': 'chest',
    'piccolo pettorale': 'chest',
    'pettorale': 'chest',
    # BACK
    'muscolo gran dorsale': 'lats',
    'gran dorsale': 'lats',
    'grande rotondo': 'lats',
    'piccolo rotondo': 'lats',
    'romboidi': 'back',
    'sottospinato': 'back',
    'infraspinato': 'back',
    'sopraspinato': 'back',
    'erettori spinali': 'lower_back',
    'erettore spinale': 'lower_back',
    'muscolo erettore della colonna vertebrale': 'lower_back',
    'multifido': 'lower_back',
    'quadrato dei lombi': 'lower_back',
    # SHOULDERS
    'deltoide anteriore': 'shoulders',
    'deltoidi anteriori': 'shoulders',
    'deltoide posteriore': 'shoulders',
    'deltoidi posteriori': 'shoulders',
    'deltoide laterale': 'shoulders',
    'deltoidi laterali': 'shoulders',
    'deltoidi lateralei': 'shoulders',  # known typo in seed
    'deltoide mediale': 'shoulders',
    # TRAPS
    'trapezio': 'traps',
    'trapezio superiore': 'traps',
    'trapezio medio': 'traps',
    'trapezio inferiore': 'traps',
    # ARMS
    'bicipite brachiale': 'biceps',
    'tricipite brachiale': 'triceps',
    'capo lungo del bicipite': 'biceps',
    'capo breve del bicipite': 'biceps',
    'capo lungo del tricipite': 'triceps',
    'brachiale': 'biceps',
    'brachioradiale': 'forearms',
    'flessori dell avambraccio': 'forearms',
    'estensori dell avambraccio': 'forearms',
    # QUADS
    'quadricipite': 'quads',
    'retto femorale': 'quads',
    'vasto laterale': 'quads',
    'vasto mediale': 'quads',
    'vastus mediais': 'quads',  # typo in seed
    'vasto intermedio': 'quads',
    # HAMS
    'femorale': 'hamstrings',
    'bicipite femorale': 'hamstrings',
    'semitendinoso': 'hamstrings',
    'semimembranoso': 'hamstrings',
    # GLUTES
    'grande gluteo': 'glutes',
    'medio gluteo': 'glutes',
    'piccolo gluteo': 'glutes',
    'gluteo medio': 'glutes',
    # CALVES
    'gastrocnemio': 'calves',
    'soleo': 'calves',
    'tibiale anteriore': 'calves',
    'tibiale posteriore': 'calves',
    # CORE
    "retto dell'addome": 'abs',
    'retto dell addome': 'abs',
    'retto addominale': 'abs',
    'trasverso addominale': 'abs',
    'obliquo esterno': 'obliques',
    'obliquo interno': 'obliques',
    'obliqui esterni': 'obliques',
    'obliqui interni': 'obliques',
    # HIPS / ADDUCTOR
    'adduttore': 'adductors',
    'adduttore lungo': 'adductors',
    'adduttore breve': 'adductors',
    'grande adduttore': 'adductors',
    'gracile': 'adductors',
    'pettineo': 'adductors',
    'ileopsoas': 'quads',  # hip flexor — closest mapping for volume purposes
    'psoas': 'quads',
    'iliaco': 'quads',
    'sartorio': 'quads',
    'tensore della fascia lata': 'glutes',
    # NECK
    'sternocleidomastoideo': 'neck',
    'scaleni': 'neck',
}


def _norm(s: str) -> str:
    if not s:
        return ''
    s = unicodedata.normalize('NFKD', s)
    s = ''.join(c for c in s if not unicodedata.combining(c))
    s = re.sub(r"['`]", ' ', s)
    s = re.sub(r'[\s_/-]+', ' ', s.strip().lower())
    return s


def _resolve_tokens(raw: str, slug_to_obj: dict) -> list:
    if not raw:
        return []
    matched = []
    seen = set()
    tokens = re.split(r'[,/;|+]| e ', raw)
    for tok in tokens:
        key = _norm(tok)
        if not key:
            continue
        slug = ANATOMICAL_ALIASES.get(key)
        # Try partial: "deltoide anteriore destro" — strip extras
        if not slug:
            for alias_key, alias_slug in ANATOMICAL_ALIASES.items():
                if alias_key in key:
                    slug = alias_slug
                    break
        if slug and slug in slug_to_obj and slug not in seen:
            seen.add(slug)
            matched.append(slug_to_obj[slug])
    return matched


def remap(apps, schema_editor):
    Exercise = apps.get_model('workouts', 'Exercise')
    MuscleGroup = apps.get_model('workouts', 'MuscleGroup')

    muscle_map = {m.slug: m for m in MuscleGroup.objects.all()}

    updated = 0
    for ex in Exercise.objects.all().iterator():
        # Only re-process when no primary muscles linked yet
        if ex.primary_muscles.exists():
            continue
        primary_raw = ex.primary_muscle or ex.target_muscle_group or ''
        primary_objs = _resolve_tokens(primary_raw, muscle_map)
        if primary_objs:
            ex.primary_muscles.add(*primary_objs)
            updated += 1

        if not ex.secondary_muscles.exists():
            secondary_objs = _resolve_tokens(ex.secondary_muscle or '', muscle_map)
            if secondary_objs:
                ex.secondary_muscles.add(*secondary_objs)

    print(f"\n[workouts] Anatomical remap: {updated} exercises updated.\n")


def noop_reverse(apps, schema_editor):
    pass


class Migration(migrations.Migration):
    dependencies = [
        ('workouts', '0009_seed_taxonomy'),
    ]
    operations = [
        migrations.RunPython(remap, noop_reverse),
    ]
