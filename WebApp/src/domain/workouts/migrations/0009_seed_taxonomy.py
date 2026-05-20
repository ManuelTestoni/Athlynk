"""
Seed Sport + MuscleGroup catalogs and migrate legacy text columns on Exercise
(`exercise_classification`, `target_muscle_group`, `primary_muscle`,
`secondary_muscle`) into normalized M2M relations.

Unmatched rows are collected and dumped to an HTML report under
MEDIA_ROOT/migration_reports/ for manual curation in Django admin.
"""

from __future__ import annotations

import datetime
import os
import re
import unicodedata

from django.conf import settings
from django.db import migrations


# --- Seed data ---------------------------------------------------------------

SPORTS = [
    # (slug, name, category, icon, order)
    ('bodybuilding',  'Bodybuilding',  'FORCE',     'ph-barbell',           10),
    ('powerlifting',  'Powerlifting',  'FORCE',     'ph-barbell',           20),
    ('weightlifting', 'Pesistica',     'FORCE',     'ph-barbell',           30),
    ('crossfit',      'CrossFit',      'FORCE',     'ph-lightning',         40),
    ('functional',    'Funzionale',    'FORCE',     'ph-person-simple-run', 50),
    ('calisthenics',  'Calisthenics',  'FORCE',     'ph-person-arms-spread', 60),
    ('running',       'Running',       'ENDURANCE', 'ph-person-simple-run', 70),
    ('cycling',       'Ciclismo',      'ENDURANCE', 'ph-bicycle',           80),
    ('swimming',      'Nuoto',         'ENDURANCE', 'ph-swimming-pool',     90),
    ('soccer',        'Calcio',        'TEAM',      'ph-soccer-ball',      100),
    ('basketball',    'Basket',        'TEAM',      'ph-basketball',       110),
    ('volleyball',    'Pallavolo',     'TEAM',      'ph-volleyball',       120),
    ('tennis',        'Tennis',        'RACKET',    'ph-tennis-ball',      130),
    ('padel',         'Padel',         'RACKET',    'ph-tennis-ball',      140),
    ('boxing',        'Boxe',          'COMBAT',    'ph-boxing-glove',     150),
    ('mma',           'MMA',           'COMBAT',    'ph-boxing-glove',     160),
    ('yoga',          'Yoga',          'OTHER',     'ph-person-simple-tai-chi', 170),
    ('general',       'Generico',      'OTHER',     'ph-stack',            999),
]


MUSCLE_GROUPS = [
    # (slug, name, region, color_token, order)
    ('chest',     'Petto',         'UPPER', 'mg-chest',     10),
    ('back',      'Schiena',       'UPPER', 'mg-back',      20),
    ('lats',      'Dorsali',       'UPPER', 'mg-back',      21),
    ('traps',     'Trapezi',       'UPPER', 'mg-back',      22),
    ('shoulders', 'Spalle',        'UPPER', 'mg-shoulders', 30),
    ('biceps',    'Bicipiti',      'UPPER', 'mg-biceps',    40),
    ('triceps',   'Tricipiti',     'UPPER', 'mg-triceps',   50),
    ('forearms',  'Avambracci',    'UPPER', 'mg-forearms',  60),
    ('quads',     'Quadricipiti',  'LOWER', 'mg-quads',     70),
    ('hamstrings', 'Femorali',     'LOWER', 'mg-hams',      80),
    ('glutes',    'Glutei',        'LOWER', 'mg-glutes',    90),
    ('calves',    'Polpacci',      'LOWER', 'mg-calves',   100),
    ('adductors', 'Adduttori',     'LOWER', 'mg-quads',    110),
    ('abductors', 'Abduttori',     'LOWER', 'mg-glutes',   120),
    ('abs',       'Addome',        'CORE',  'mg-abs',      130),
    ('obliques',  'Obliqui',       'CORE',  'mg-abs',      140),
    ('lower_back', 'Lombari',      'CORE',  'mg-back',     150),
    ('neck',      'Collo',         'UPPER', 'mg-other',    160),
    ('other',     'Altro',         'UPPER', 'mg-other',    900),
]


# --- Aliasing tables (lowercase, accent-stripped) ---------------------------

SPORT_ALIASES = {
    'bb': 'bodybuilding',
    'body building': 'bodybuilding',
    'pl': 'powerlifting',
    'power lifting': 'powerlifting',
    'cross fit': 'crossfit',
    'cross-fit': 'crossfit',
    'wl': 'weightlifting',
    'olympic weightlifting': 'weightlifting',
    'olympic lifting': 'weightlifting',
    'sollevamento pesi': 'weightlifting',
    'pesistica olimpica': 'weightlifting',
    'corsa': 'running',
    'bici': 'cycling',
    'ciclismo': 'cycling',
    'nuoto': 'swimming',
    'football': 'soccer',
    'pallacanestro': 'basketball',
    'pallavolo': 'volleyball',
    'racchetta': 'tennis',
    'boxe': 'boxing',
    'pugilato': 'boxing',
    'arti marziali miste': 'mma',
    'funzionale': 'functional',
    'functional training': 'functional',
    'calisthenics': 'calisthenics',
    'corpo libero': 'calisthenics',
    'generico': 'general',
    'general': 'general',
    'altro': 'general',
    'other': 'general',
    '': None,
}

MUSCLE_ALIASES = {
    'pettorali': 'chest',
    'petto': 'chest',
    'chest': 'chest',
    'schiena': 'back',
    'back': 'back',
    'dorsali': 'lats',
    'dorso': 'lats',
    'lats': 'lats',
    'gran dorsale': 'lats',
    'trapezi': 'traps',
    'trapezio': 'traps',
    'spalle': 'shoulders',
    'deltoidi': 'shoulders',
    'deltoide': 'shoulders',
    'shoulders': 'shoulders',
    'bicipiti': 'biceps',
    'bicipite': 'biceps',
    'biceps': 'biceps',
    'tricipiti': 'triceps',
    'tricipite': 'triceps',
    'triceps': 'triceps',
    'avambracci': 'forearms',
    'avambraccio': 'forearms',
    'forearms': 'forearms',
    'quadricipiti': 'quads',
    'quadricipite': 'quads',
    'quads': 'quads',
    'femorali': 'hamstrings',
    'hamstring': 'hamstrings',
    'hamstrings': 'hamstrings',
    'ischiocrurali': 'hamstrings',
    'glutei': 'glutes',
    'gluteo': 'glutes',
    'glutes': 'glutes',
    'polpacci': 'calves',
    'polpaccio': 'calves',
    'calves': 'calves',
    'adduttori': 'adductors',
    'abduttori': 'abductors',
    'addome': 'abs',
    'addominali': 'abs',
    'abs': 'abs',
    'core': 'abs',
    'obliqui': 'obliques',
    'lombari': 'lower_back',
    'lower back': 'lower_back',
    'low back': 'lower_back',
    'collo': 'neck',
    'gambe': None,  # too generic — handled below as multi-mapping
    'braccia': None,
    'parte superiore': None,
    'parte inferiore': None,
    'corpo libero': None,
    'full body': None,
    'altro': 'other',
    'other': 'other',
    '': None,
}

# Generic terms map to a *set* of muscles (multi-mapping)
MUSCLE_MULTI_ALIASES = {
    'gambe': ['quads', 'hamstrings', 'glutes', 'calves'],
    'braccia': ['biceps', 'triceps', 'forearms'],
    'parte superiore': ['chest', 'back', 'shoulders'],
    'parte inferiore': ['quads', 'hamstrings', 'glutes'],
}


def _norm(s: str) -> str:
    if not s:
        return ''
    s = unicodedata.normalize('NFKD', s)
    s = ''.join(c for c in s if not unicodedata.combining(c))
    s = re.sub(r'[\s_/-]+', ' ', s.strip().lower())
    return s


def _resolve_muscles(raw: str, slug_to_obj: dict) -> tuple[list, list]:
    """Return (matched_objs, unmatched_tokens) for a free-text cell.

    Supports multi-value cells like "Petto, Tricipiti" or "Quadricipiti / Glutei".
    """
    if not raw:
        return [], []
    matched, unmatched = [], []
    tokens = re.split(r'[,/;|+]| e ', raw)
    for tok in tokens:
        key = _norm(tok)
        if not key:
            continue
        if key in MUSCLE_MULTI_ALIASES:
            for slug in MUSCLE_MULTI_ALIASES[key]:
                if slug in slug_to_obj:
                    matched.append(slug_to_obj[slug])
            continue
        target = MUSCLE_ALIASES.get(key, key)
        if target and target in slug_to_obj:
            matched.append(slug_to_obj[target])
        else:
            unmatched.append(tok.strip())
    # dedupe while preserving order
    seen = set()
    deduped = []
    for m in matched:
        if m.pk not in seen:
            seen.add(m.pk)
            deduped.append(m)
    return deduped, unmatched


def _resolve_sport(raw: str, slug_to_obj: dict):
    if not raw:
        return None, None
    key = _norm(raw)
    target = SPORT_ALIASES.get(key, key)
    if target is None:
        return None, None
    if target in slug_to_obj:
        return slug_to_obj[target], None
    return None, raw.strip()


def _write_unmatched_report(unmatched_sports, unmatched_muscles, totals):
    report_dir = os.path.join(getattr(settings, 'MEDIA_ROOT', '/tmp'), 'migration_reports')
    os.makedirs(report_dir, exist_ok=True)
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    path = os.path.join(report_dir, f'taxonomy_unmatched_{ts}.html')

    def _rows(items):
        if not items:
            return '<tr><td colspan="3" class="muted">Nessun valore non mappato.</td></tr>'
        rows = []
        # items is dict raw_value -> [exercise ids]
        for raw, ids in sorted(items.items(), key=lambda kv: (-len(kv[1]), kv[0])):
            ids_str = ', '.join(str(i) for i in ids[:25])
            more = f' (+{len(ids) - 25} altri)' if len(ids) > 25 else ''
            rows.append(
                f'<tr><td><code>{raw}</code></td>'
                f'<td>{len(ids)}</td>'
                f'<td class="muted">{ids_str}{more}</td></tr>'
            )
        return '\n'.join(rows)

    html = f"""<!doctype html>
<html lang="it"><head><meta charset="utf-8">
<title>Report migrazione tassonomia esercizi</title>
<style>
  body {{ font: 14px/1.5 -apple-system, BlinkMacSystemFont, 'Inter', sans-serif;
         color: #1c1917; background: #faf7f0; padding: 32px; max-width: 960px; margin: auto; }}
  h1 {{ font-family: 'Bodoni Moda', Georgia, serif; font-weight: 500; color: #1c1917; }}
  h2 {{ font-family: 'Bodoni Moda', Georgia, serif; font-weight: 500; margin-top: 36px; }}
  table {{ width: 100%; border-collapse: collapse; margin-top: 12px; background: #fff;
           border: 1px solid #d9d2c4; }}
  th, td {{ text-align: left; padding: 8px 12px; border-bottom: 1px solid #e7e2d5; font-size: 13px; }}
  th {{ background: #f4efe4; font-weight: 600; }}
  .muted {{ color: #78716c; }}
  code {{ background: #f4efe4; padding: 2px 6px; border-radius: 3px; font-size: 12px; }}
  .summary {{ padding: 12px 16px; background: #fff; border-left: 3px solid #8a6a3b; margin: 16px 0; }}
</style></head>
<body>
<h1>Report migrazione tassonomia esercizi</h1>
<p class="muted">Generato {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
<div class="summary">
  <strong>Riepilogo</strong><br>
  Esercizi processati: {totals['exercises']}<br>
  Match muscolo primario: {totals['primary_matched']}<br>
  Match muscolo secondario: {totals['secondary_matched']}<br>
  Match sport: {totals['sport_matched']}<br>
  Valori muscolo non mappati: {len(unmatched_muscles)}<br>
  Valori sport non mappati: {len(unmatched_sports)}
</div>

<h2>Sport non mappati</h2>
<table><thead><tr><th>Valore originale</th><th>Esercizi</th><th>ID (primi 25)</th></tr></thead>
<tbody>{_rows(unmatched_sports)}</tbody></table>

<h2>Gruppi muscolari non mappati</h2>
<table><thead><tr><th>Valore originale</th><th>Esercizi</th><th>ID (primi 25)</th></tr></thead>
<tbody>{_rows(unmatched_muscles)}</tbody></table>

<p class="muted" style="margin-top: 32px;">
  Aggiungi un alias in <code>0009_seed_taxonomy.py</code> oppure correggi manualmente
  ogni esercizio dall'admin Django.
</p>
</body></html>"""
    with open(path, 'w', encoding='utf-8') as f:
        f.write(html)
    return path


# --- Forward operation -------------------------------------------------------

def seed_and_migrate(apps, schema_editor):
    Sport = apps.get_model('workouts', 'Sport')
    MuscleGroup = apps.get_model('workouts', 'MuscleGroup')
    Exercise = apps.get_model('workouts', 'Exercise')

    # 1) Seed sports
    for slug, name, category, icon, order in SPORTS:
        Sport.objects.update_or_create(
            slug=slug,
            defaults={'name': name, 'category': category, 'icon': icon,
                      'order': order, 'is_system': True},
        )

    # 2) Seed muscle groups
    for slug, name, region, color_token, order in MUSCLE_GROUPS:
        MuscleGroup.objects.update_or_create(
            slug=slug,
            defaults={'name': name, 'region': region,
                      'color_token': color_token, 'order': order},
        )

    sport_map = {s.slug: s for s in Sport.objects.all()}
    muscle_map = {m.slug: m for m in MuscleGroup.objects.all()}

    # 3) Walk exercises
    unmatched_sports: dict[str, list[int]] = {}
    unmatched_muscles: dict[str, list[int]] = {}
    totals = {'exercises': 0, 'primary_matched': 0,
              'secondary_matched': 0, 'sport_matched': 0}

    for ex in Exercise.objects.all().iterator():
        totals['exercises'] += 1

        # Sport
        sport_obj, sport_unmatched = _resolve_sport(ex.exercise_classification or '', sport_map)
        if sport_obj:
            ex.sports.add(sport_obj)
            totals['sport_matched'] += 1
        elif sport_unmatched:
            unmatched_sports.setdefault(sport_unmatched, []).append(ex.id)

        # Primary muscles
        primary_objs, primary_unmatched = _resolve_muscles(
            ex.primary_muscle or ex.target_muscle_group or '', muscle_map,
        )
        if primary_objs:
            ex.primary_muscles.add(*primary_objs)
            totals['primary_matched'] += 1
        for tok in primary_unmatched:
            unmatched_muscles.setdefault(tok, []).append(ex.id)

        # Secondary muscles
        secondary_objs, secondary_unmatched = _resolve_muscles(ex.secondary_muscle or '', muscle_map)
        if secondary_objs:
            ex.secondary_muscles.add(*secondary_objs)
            totals['secondary_matched'] += 1
        for tok in secondary_unmatched:
            unmatched_muscles.setdefault(tok, []).append(ex.id)

    # 4) Write HTML report
    try:
        path = _write_unmatched_report(unmatched_sports, unmatched_muscles, totals)
        print(f"\n[workouts] Taxonomy migration report: {path}\n")
    except Exception as exc:  # noqa: BLE001
        print(f"\n[workouts] Could not write report ({exc}); summary below:\n"
              f"  exercises={totals['exercises']} primary={totals['primary_matched']} "
              f"secondary={totals['secondary_matched']} sport={totals['sport_matched']}\n"
              f"  unmatched_sports={len(unmatched_sports)} unmatched_muscles={len(unmatched_muscles)}\n")


def noop_reverse(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ('workouts', '0008_musclegroup_exercise_coach_notes_and_more'),
    ]

    operations = [
        migrations.RunPython(seed_and_migrate, noop_reverse),
    ]
