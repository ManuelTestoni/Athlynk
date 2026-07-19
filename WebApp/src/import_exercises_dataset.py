#!/usr/bin/env python
"""
Standalone importer: hasaneyldrm/exercises-dataset -> Exercise table.

Usage (from WebApp/src):
    ../../venv/bin/python import_exercises_dataset.py                    # full import (1324 exercises)
    ../../venv/bin/python import_exercises_dataset.py --limit 20         # quick test batch
    ../../venv/bin/python import_exercises_dataset.py --dry-run          # validate mapping, no Exercise/media writes
    ../../venv/bin/python import_exercises_dataset.py --yes              # skip confirmation (CI/script use)
    ../../venv/bin/python import_exercises_dataset.py --repo-path /path  # reuse an existing local clone
    ../../venv/bin/python import_exercises_dataset.py --batch-size 50
    ../../venv/bin/python import_exercises_dataset.py --only-lever         # backfill just the "lever" records, no wipe

Behavior:
- Prompts for confirmation, then wipes ALL WorkoutPlan rows (cascading to
  WorkoutDay/WorkoutExercise/WorkoutAssignment/sessions/logs) and ALL Exercise
  rows (custom included), since every plan/exercise references the catalog
  being replaced. Same destructive full-replace pattern as
  domain/workouts/management/commands/import_wger_exercises.py.
  --only-lever skips this confirmation/wipe entirely (see below).
- Clones https://github.com/hasaneyldrm/exercises-dataset.git (shallow) into
  --repo-path if it doesn't already exist there.
- Normalizes every record whose name starts with the word "lever" (a
  leverage-machine marker in the dataset) by stripping that leading word --
  e.g. "lever chest press" -> "chest press" -- instead of dropping the
  exercise (71 of 1324 records affected). --only-lever filters the dataset
  down to just these records and imports/updates them via the normal
  per-record path (update_or_create keyed on dataset_id, so it's safe to
  re-run) without touching anything else already in the DB.
- Loads data/exercises.json (1324 records), resolves category / equipment /
  muscles against local taxonomy tables (ExerciseCategory, Equipment,
  MuscleGroup), auto-creating any category/equipment value not covered by the
  curated IT-translation dicts below (muscles are matched against the fixed,
  already-seeded MuscleGroup slugs only -- unmapped ones are reported, never
  auto-created).
- Converts each exercise's static jpg thumbnail -> WebP (cover_image) and
  animated gif -> animated WebP (demo_gif), uploads both through Django's
  default_storage (Supabase S3 in production, local filesystem in dev).
- Commits DB writes in batches of --batch-size (default 100) inside
  transaction.atomic(); media uploads happen outside the transaction but are
  safe to redo (re-running matches by unique dataset_id).
- --dry-run resolves every mapping (category/equipment/muscle/slug) and checks
  that gif/jpg files exist on disk, WITHOUT touching the Exercise table, the
  WorkoutPlan wipe, or any storage upload. It still get_or_creates
  category/equipment rows (harmless, idempotent lookup-table population) so
  the mapping can be validated end to end.

Media license note: images/gifs are (c) Gym Visual (gymvisual.com), NOT MIT,
capped at 180x180, and require attribution. license_title/license_author on
each imported Exercise carry that attribution. Commercial redistribution
requires a separate license from Gym Visual -- see NOTICE.md in the source
repo.
"""
import argparse
import io
import json
import os
import re
import subprocess
import sys
import zlib
from pathlib import Path

import django

# Bootstrap Django
SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.core.files.base import ContentFile
from django.db import transaction
from django.utils.text import slugify
from PIL import Image, ImageSequence
from tqdm import tqdm

from config.services.images import to_webp
from domain.workouts.models import Exercise, ExerciseCategory, Equipment, MuscleGroup, WorkoutPlan

REPO_URL = 'https://github.com/hasaneyldrm/exercises-dataset.git'
DEFAULT_REPO_PATH = SCRIPT_DIR.parents[1] / '.cache' / 'exercises-dataset'
ATTRIBUTION_LICENSE_TITLE = 'Gym Visual — attribution required, licenza commerciale separata'

# dataset body_part (closed 10-value enum per data/exercises.schema.json) ->
# (synthetic wger_id, Italian name). ExerciseCategory.wger_id is unique+NOT
# NULL, so negative ids are reserved here to avoid colliding with real wger.de
# ids used by import_wger_exercises.py (CATEGORY_IT there uses 8-15).
BODY_PART_IT = {
    'back': (-1, 'Schiena'),
    'cardio': (-2, 'Cardio'),
    'chest': (-3, 'Petto'),
    'lower arms': (-4, 'Avambracci'),
    'lower legs': (-5, 'Polpacci'),
    'neck': (-6, 'Collo'),
    'shoulders': (-7, 'Spalle'),
    'upper arms': (-8, 'Braccia'),
    'upper legs': (-9, 'Gambe'),
    'waist': (-10, 'Addominali'),
}

# dataset equipment -> (synthetic wger_id, Italian name). Equipment.wger_id is
# also unique+NOT NULL. Where the concept overlaps an existing wger.de-seeded
# row (see EQUIPMENT_IT in import_wger_exercises.py), reuse that row's real
# wger_id instead of creating a duplicate; everything else gets a negative id.
EQUIPMENT_IT = {
    'barbell': (1, 'Bilanciere'),
    'ez barbell': (2, 'Bilanciere EZ'),
    'dumbbell': (3, 'Manubrio'),
    'stability ball': (5, 'Fitball'),
    'body weight': (7, 'Corpo libero'),
    'kettlebell': (10, 'Kettlebell'),
    'resistance band': (11, 'Elastico'),
    'band': (11, 'Elastico'),
    'olympic barbell': (-11, 'Bilanciere olimpionico'),
    'cable': (-12, 'Cavo'),
    'assisted': (-13, 'Assistito'),
    'bosu ball': (-14, 'Bosu'),
    'elliptical machine': (-15, 'Ellittica'),
    'hammer': (-16, 'Hammer'),
    'leverage machine': (-17, 'Macchina a leva'),
    'medicine ball': (-18, 'Palla medica'),
    'roller': (-19, 'Rullo'),
    'rope': (-20, 'Corda'),
    'skierg machine': (-21, 'SkiErg'),
    'sled machine': (-22, 'Slitta'),
    'smith machine': (-23, 'Smith machine'),
    'stationary bike': (-24, 'Cyclette'),
    'stepmill machine': (-25, 'Stepmill'),
    'tire': (-26, 'Pneumatico'),
    'trap bar': (-27, 'Trap bar'),
    'upper body ergometer': (-28, 'Ergometro braccia'),
    'weighted': (-29, 'Zavorrato'),
    'wheel roller': (-30, 'Ruota addominali'),
}

# dataset target / secondary_muscles strings -> existing MuscleGroup.slug
# (already seeded: abs, obliques, lower_back, quads, hamstrings, glutes,
# calves, adductors, abductors, chest, back, lats, traps, shoulders, biceps,
# triceps, forearms, neck, other). Every key below was verified against the
# full 1324-record dataset (all distinct `target` and `secondary_muscles`
# values), not guessed from ExerciseDB's generic vocabulary. Values with no
# sensible dedicated group map to 'other'; anything not in this dict is left
# unmapped (reported, not guessed).
MUSCLE_TO_SLUG = {
    # primary `target` values
    'abs': 'abs', 'pectorals': 'chest', 'biceps': 'biceps', 'glutes': 'glutes',
    'delts': 'shoulders', 'triceps': 'triceps', 'upper back': 'back', 'lats': 'lats',
    'calves': 'calves', 'quads': 'quads', 'forearms': 'forearms',
    'cardiovascular system': 'other', 'hamstrings': 'hamstrings', 'spine': 'lower_back',
    'traps': 'traps', 'adductors': 'adductors', 'serratus anterior': 'chest',
    'abductors': 'abductors', 'levator scapulae': 'neck',
    # `secondary_muscles` values (union, dedup with the above)
    'shoulders': 'shoulders', 'quadriceps': 'quads', 'core': 'abs', 'chest': 'chest',
    'hip flexors': 'other', 'obliques': 'obliques', 'lower back': 'lower_back',
    'rhomboids': 'back', 'trapezius': 'traps', 'deltoids': 'shoulders',
    'rear deltoids': 'shoulders', 'brachialis': 'biceps', 'back': 'back',
    'ankles': 'calves', 'feet': 'other', 'rotator cuff': 'shoulders',
    'latissimus dorsi': 'lats', 'ankle stabilizers': 'calves', 'soleus': 'calves',
    'wrists': 'forearms', 'upper chest': 'chest', 'wrist flexors': 'forearms',
    'wrist extensors': 'forearms', 'abdominals': 'abs', 'sternocleidomastoid': 'neck',
    'hands': 'forearms', 'groin': 'adductors', 'grip muscles': 'forearms',
    'lower abs': 'abs', 'inner thighs': 'adductors', 'shins': 'calves',
}


def _unique_slug(name, used):
    base = slugify(name)[:200] or 'esercizio'
    candidate = base
    n = 2
    while candidate in used or Exercise.objects.filter(slug=candidate).exists():
        suffix = f'-{n}'
        candidate = (base[:200 - len(suffix)] + suffix)
        n += 1
    used.add(candidate)
    return candidate


def resolve_slug(dataset_id: str, name: str, used_slugs: set) -> str:
    """Reuse the current slug on re-import; only mint a fresh one for a
    brand-new dataset_id. Computed *before* update_or_create so the INSERT
    never relies on SlugField's empty-string default (which collides on the
    unique constraint from the second row onward -- see
    import_wger_exercises.py's post-hoc slug fix, which has that bug)."""
    existing = Exercise.objects.filter(dataset_id=dataset_id).values_list('slug', flat=True).first()
    if existing:
        used_slugs.add(existing)
        return existing
    return _unique_slug(name, used_slugs)


def ensure_repo(repo_path: Path) -> Path:
    if (repo_path / 'data' / 'exercises.json').exists():
        return repo_path
    repo_path.parent.mkdir(parents=True, exist_ok=True)
    print(f'>> Clono {REPO_URL} in {repo_path} ...')
    subprocess.run(['git', 'clone', '--depth', '1', REPO_URL, str(repo_path)], check=True)
    return repo_path


def pick_text(field: dict | None):
    """it -> en -> first available, matching the app's IT-first convention
    (see _pick_translation in import_wger_exercises.py)."""
    if not field:
        return None
    return field.get('it') or field.get('en') or next(iter(field.values()), None)


_LEVER_PREFIX_RE = re.compile(r'^lever\b\s*', re.IGNORECASE)


def strip_lever_prefix(name: str) -> str:
    """Drop a leading 'lever' word (the dataset's leverage-machine marker),
    e.g. 'lever chest press' -> 'chest press'. Word boundary means
    'leverage ...' (a different word) is left untouched."""
    return _LEVER_PREFIX_RE.sub('', name, count=1)


def gif_to_animated_webp(gif_path: Path, *, quality: int = 80) -> ContentFile:
    """Re-encode an animated GIF as an animated WebP, preserving all frames.

    Unlike config.services.images.to_webp() (single-frame, used for static
    uploads app-wide), this walks every frame via ImageSequence and re-saves
    with save_all=True so the exercise demo keeps animating client-side.
    """
    with Image.open(gif_path) as im:
        frames = []
        durations = []
        for frame in ImageSequence.Iterator(im):
            frames.append(frame.convert('RGBA'))
            durations.append(frame.info.get('duration', 100))
        loop = im.info.get('loop', 0)

    buf = io.BytesIO()
    frames[0].save(
        buf, format='WEBP', save_all=True, append_images=frames[1:],
        duration=durations, loop=loop, quality=quality, method=6,
    )
    buf.seek(0)
    return ContentFile(buf.read())


def jpg_to_static_webp(jpg_path: Path) -> ContentFile:
    with open(jpg_path, 'rb') as f:
        return to_webp(f)


class TaxonomyCache:
    def __init__(self):
        self.categories = {}
        self.equipment = {}
        self.muscle_by_slug = {mg.slug: mg for mg in MuscleGroup.objects.all()}

    def category_for(self, body_part: str) -> ExerciseCategory:
        if body_part not in self.categories:
            wger_id, name_it = BODY_PART_IT[body_part]
            cat, _ = ExerciseCategory.objects.get_or_create(
                wger_id=wger_id, defaults={'name_en': body_part, 'name_it': name_it},
            )
            self.categories[body_part] = cat
        return self.categories[body_part]

    def equipment_for(self, name: str) -> Equipment:
        if name not in self.equipment:
            entry = EQUIPMENT_IT.get(name)
            if entry:
                wger_id, name_it = entry
            else:
                # Unknown equipment name (not in the curated list above): a
                # stable negative id derived from the name, so a re-run
                # get_or_creates the same row instead of duplicating it.
                wger_id = -1000 - (zlib.crc32(name.encode()) % 1_000_000)
                name_it = name.title()
            eq, _ = Equipment.objects.get_or_create(
                wger_id=wger_id, defaults={'name_en': name, 'name_it': name_it},
            )
            self.equipment[name] = eq
        return self.equipment[name]

    def muscle_for(self, name: str | None) -> MuscleGroup | None:
        slug = MUSCLE_TO_SLUG.get(name) if name else None
        return self.muscle_by_slug.get(slug) if slug else None


def build_exercise_fields(record: dict, taxonomy: 'TaxonomyCache') -> dict:
    name = strip_lever_prefix(record['name'].strip())[:200]
    description = pick_text(record.get('instructions'))
    steps = record.get('instruction_steps') or {}
    instruction_steps = steps.get('it') or steps.get('en') or next(iter(steps.values()), None)

    return {
        'name': name,
        'description': description,
        'instruction_steps': instruction_steps,
        'muscle_detail': record.get('muscle_group') or None,
        'license_title': ATTRIBUTION_LICENSE_TITLE,
        'license_author': record.get('attribution') or None,
        'is_custom': False,
        'category': taxonomy.category_for(record['body_part']),
    }


def process_batch(batch, taxonomy, used_slugs, unmapped_muscles, repo_path, args, pbar):
    imported = 0
    skipped_media = 0
    lever_stripped = 0

    with transaction.atomic():
        for record in batch:
            pbar.update(1)

            if _LEVER_PREFIX_RE.match(record['name'].strip()):
                lever_stripped += 1
            fields = build_exercise_fields(record, taxonomy)

            equipment_name = record.get('equipment')
            equipment_obj = taxonomy.equipment_for(equipment_name) if equipment_name else None

            primary = taxonomy.muscle_for(record.get('target'))
            secondary_objs = []
            for m in record.get('secondary_muscles') or []:
                mg = taxonomy.muscle_for(m)
                if mg:
                    secondary_objs.append(mg)
                else:
                    unmapped_muscles.add(m)

            gif_path = repo_path / record['gif_url'] if record.get('gif_url') else None
            jpg_path = repo_path / record['image'] if record.get('image') else None

            if args.dry_run:
                if gif_path and not gif_path.exists():
                    skipped_media += 1
                if jpg_path and not jpg_path.exists():
                    skipped_media += 1
                imported += 1
                continue

            fields['slug'] = resolve_slug(record['id'], fields['name'], used_slugs)
            exercise, _created = Exercise.objects.update_or_create(
                dataset_id=record['id'], defaults=fields,
            )
            exercise.equipment.set([equipment_obj] if equipment_obj else [])
            exercise.primary_muscles.set([primary] if primary else [])
            exercise.secondary_muscles.set(secondary_objs)

            if not args.skip_media:
                if gif_path and gif_path.exists():
                    webp = gif_to_animated_webp(gif_path)
                    exercise.demo_gif.save(f"{record['id']}.webp", webp, save=True)
                elif gif_path:
                    skipped_media += 1
                if jpg_path and jpg_path.exists():
                    webp = jpg_to_static_webp(jpg_path)
                    exercise.cover_image.save(f"{record['id']}.webp", webp, save=True)
                elif jpg_path:
                    skipped_media += 1

            imported += 1

    return imported, skipped_media, lever_stripped


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--repo-path', type=Path, default=DEFAULT_REPO_PATH)
    parser.add_argument('--batch-size', type=int, default=100)
    parser.add_argument('--limit', type=int, default=None, help='Importa solo le prime N schede (test rapido).')
    parser.add_argument('--yes', action='store_true', help='Salta la conferma interattiva.')
    parser.add_argument('--dry-run', action='store_true', help='Valida mapping/slug/file senza scrivere Exercise o media.')
    parser.add_argument('--skip-media', action='store_true', help='Salta conversione/upload gif+jpg (solo dati testuali).')
    parser.add_argument('--only-lever', action='store_true',
                         help="Backfill mirato: importa/aggiorna solo i record il cui nome inizia per "
                              "'lever' (nome normalizzato, prefisso tolto), senza toccare o cancellare "
                              "nient'altro (nessun wipe di WorkoutPlan/Exercise).")
    args = parser.parse_args()

    if not args.only_lever:
        existing_ex = Exercise.objects.count()
        existing_plans = WorkoutPlan.objects.count()
        if existing_ex or existing_plans:
            print(f'>> Trovati {existing_ex} esercizi e {existing_plans} schede esistenti.')
            if not args.dry_run:
                if not args.yes:
                    ans = input('   Cancello TUTTO (schede + esercizi, custom incluso) e reimporto dal dataset? [s/N]: ').strip().lower()
                    if ans not in ('s', 'si', 'y', 'yes'):
                        print('Annullato.')
                        sys.exit(0)
                with transaction.atomic():
                    deleted_plans, _ = WorkoutPlan.objects.all().delete()
                    deleted_ex, _ = Exercise.objects.all().delete()
                    print(f'>> Eliminate {deleted_plans} schede e {deleted_ex} esercizi (cascade incluso).')

    repo_path = ensure_repo(args.repo_path)
    data_path = repo_path / 'data' / 'exercises.json'
    print(f'>> Carico {data_path} ...')
    records = json.loads(data_path.read_text())
    if args.only_lever:
        records = [r for r in records if _LEVER_PREFIX_RE.match(r['name'].strip())]
        print(f'>> --only-lever: {len(records)} record selezionati, nessuna cancellazione.')
    if args.limit is not None:
        records = records[:args.limit]
    print(f'>> {len(records)} record da importare.')

    taxonomy = TaxonomyCache()
    used_slugs = set(Exercise.objects.values_list('slug', flat=True))
    unmapped_muscles = set()

    imported = 0
    skipped_media = 0
    lever_stripped = 0

    with tqdm(total=len(records), desc='esercizi', unit='ex') as pbar:
        for start in range(0, len(records), args.batch_size):
            batch = records[start:start + args.batch_size]
            n, sm, ls = process_batch(batch, taxonomy, used_slugs, unmapped_muscles, repo_path, args, pbar)
            imported += n
            skipped_media += sm
            lever_stripped += ls

    mode = 'DRY-RUN (nessuna scrittura Exercise/media)' if args.dry_run else 'completato'
    print(f'== {mode}. Importati: {imported}  |  Nome "lever" normalizzato: {lever_stripped}  |  '
          f'Media mancanti su disco: {skipped_media}  |  '
          f'Totale tabella: {Exercise.objects.count() if not args.dry_run else "n/d"}')
    if unmapped_muscles:
        print(f'>> Muscoli non mappati alla tassonomia ({len(unmapped_muscles)}): {sorted(unmapped_muscles)}')


if __name__ == '__main__':
    main()
