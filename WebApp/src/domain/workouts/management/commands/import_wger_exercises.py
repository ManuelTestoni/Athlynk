"""Import the exercise catalog from the wger.de public API.

Usage:
    python manage.py import_wger_exercises              # full import (821 exercises)
    python manage.py import_wger_exercises --limit 20    # quick test batch

Behavior:
- Prompts for confirmation, then wipes ALL WorkoutPlan rows (cascading to
  WorkoutDay/WorkoutExercise/WorkoutAssignment/sessions/logs) and ALL Exercise
  rows (custom included), since every plan/exercise references the catalog
  being replaced.
- Paginates GET {WGER_API_BASE_URL}/exerciseinfo/?limit=100, and for each
  exercise picks name/description/aliases from translations: Italian, else
  English, else the first available translation.
- Resolves category / equipment / muscles against small local lookup tables
  (ExerciseCategory, Equipment, MuscleGroup) seeded on the fly.
"""
import sys

import requests
from django.conf import settings
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils.text import slugify

from domain.workouts.models import Exercise, ExerciseCategory, Equipment, MuscleGroup, WorkoutPlan

LANGUAGE_IT = 13
LANGUAGE_EN = 2

# wger category id -> Italian label
CATEGORY_IT = {
    8: 'Braccia', 9: 'Gambe', 10: 'Addominali', 11: 'Petto',
    12: 'Schiena', 13: 'Spalle', 14: 'Polpacci', 15: 'Cardio',
}

# wger equipment id -> Italian label
EQUIPMENT_IT = {
    1: 'Bilanciere', 2: 'Bilanciere EZ', 3: 'Manubrio', 4: 'Materassino',
    5: 'Fitball', 6: 'Sbarra per trazioni', 7: 'Corpo libero', 8: 'Panca',
    9: 'Panca inclinata', 10: 'Kettlebell', 11: 'Elastico',
}

# wger muscle id -> local MuscleGroup slug (see migrations 0009/0010 seed)
MUSCLE_TO_GROUP_SLUG = {
    1: 'biceps', 2: 'shoulders', 3: 'obliques', 4: 'chest', 5: 'triceps',
    6: 'abs', 7: 'calves', 8: 'glutes', 9: 'traps', 10: 'quads',
    11: 'hamstrings', 12: 'lats', 13: 'biceps', 14: 'obliques', 15: 'calves',
}


def _pick_translation(translations):
    by_lang = {t['language']: t for t in translations}
    return by_lang.get(LANGUAGE_IT) or by_lang.get(LANGUAGE_EN) or (translations[0] if translations else None)


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


class Command(BaseCommand):
    help = 'Importa (o reimporta da zero) il catalogo esercizi da wger.de'

    def add_arguments(self, parser):
        parser.add_argument('--limit', type=int, default=None,
                             help='Importa solo le prime N schede esercizio (test rapido).')
        parser.add_argument('--yes', action='store_true',
                             help='Salta la conferma interattiva (per script/CI).')

    def handle(self, *args, **options):
        limit = options.get('limit')
        skip_confirm = options.get('yes')

        existing_ex = Exercise.objects.count()
        existing_plans = WorkoutPlan.objects.count()
        if existing_ex or existing_plans:
            self.stdout.write(self.style.WARNING(
                f'>> Trovati {existing_ex} esercizi e {existing_plans} schede esistenti.'
            ))
            if not skip_confirm:
                ans = input('   Cancello TUTTO (schede + esercizi, custom incluso) e reimporto da wger.de? [s/N]: ').strip().lower()
                if ans not in ('s', 'si', 'y', 'yes'):
                    self.stdout.write('Annullato.')
                    sys.exit(0)
            with transaction.atomic():
                deleted_plans, _ = WorkoutPlan.objects.all().delete()
                deleted_ex, _ = Exercise.objects.all().delete()
                self.stdout.write(f'>> Eliminate {deleted_plans} schede e {deleted_ex} esercizi (cascade incluso).')

        base_url = settings.WGER_API_BASE_URL.rstrip('/')
        timeout = settings.WGER_API_TIMEOUT

        self.stdout.write('>> Sincronizzo categorie ed equipaggiamento...')
        categories = {}
        for wger_id, name_it in CATEGORY_IT.items():
            cat, _ = ExerciseCategory.objects.get_or_create(
                wger_id=wger_id, defaults={'name_en': '', 'name_it': name_it},
            )
            categories[wger_id] = cat

        equipment_map = {}
        for wger_id, name_it in EQUIPMENT_IT.items():
            eq, _ = Equipment.objects.get_or_create(
                wger_id=wger_id, defaults={'name_en': '', 'name_it': name_it},
            )
            equipment_map[wger_id] = eq

        muscle_map = {}
        for wger_muscle_id, slug in MUSCLE_TO_GROUP_SLUG.items():
            mg = MuscleGroup.objects.filter(slug=slug).first()
            if mg:
                muscle_map[wger_muscle_id] = mg

        self.stdout.write('>> Scarico esercizi da wger.de...')
        url = f'{base_url}/exerciseinfo/?limit=100'
        used_slugs = set()
        imported = 0
        skipped = 0

        while url:
            resp = requests.get(url, timeout=timeout)
            resp.raise_for_status()
            payload = resp.json()

            for item in payload.get('results', []):
                if limit is not None and imported >= limit:
                    url = None
                    break

                translation = _pick_translation(item.get('translations') or [])
                if not translation or not (translation.get('name') or '').strip():
                    skipped += 1
                    continue

                name = translation['name'].strip()[:200]
                description = (translation.get('description') or '').strip() or None
                aliases = [a['alias'] for a in (translation.get('aliases') or []) if a.get('alias')]

                images = item.get('images') or []
                main_image = next((i for i in images if i.get('is_main')), images[0] if images else None)

                category_obj = categories.get((item.get('category') or {}).get('id'))

                exercise, _created = Exercise.objects.update_or_create(
                    wger_uuid=item['uuid'],
                    defaults={
                        'wger_id': item['id'],
                        'name': name,
                        'description': description,
                        'aliases': aliases or None,
                        'category': category_obj,
                        'wger_image_url': (main_image or {}).get('image') or None,
                        'license_title': ((item.get('license') or {}).get('short_name')) or None,
                        'license_author': item.get('license_author') or None,
                        'is_custom': False,
                    },
                )
                if not exercise.slug:
                    exercise.slug = _unique_slug(name, used_slugs)
                    exercise.save(update_fields=['slug'])
                else:
                    used_slugs.add(exercise.slug)

                eq_ids = [e['id'] for e in (item.get('equipment') or [])]
                exercise.equipment.set([equipment_map[i] for i in eq_ids if i in equipment_map])

                primary_ids = [m['id'] for m in (item.get('muscles') or [])]
                exercise.primary_muscles.set([muscle_map[i] for i in primary_ids if i in muscle_map])

                secondary_ids = [m['id'] for m in (item.get('muscles_secondary') or [])]
                exercise.secondary_muscles.set([muscle_map[i] for i in secondary_ids if i in muscle_map])

                imported += 1
                if imported % 50 == 0:
                    self.stdout.write(f'   [{imported}] {name[:60]}')

            if url is None:
                break
            url = payload.get('next')

        self.stdout.write(self.style.SUCCESS(
            f'== Fatto. Importati: {imported}  |  Saltati (senza traduzione): {skipped}  |  '
            f'Totale tabella: {Exercise.objects.count()}'
        ))
