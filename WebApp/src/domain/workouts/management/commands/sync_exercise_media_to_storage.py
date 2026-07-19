"""Backfill Exercise demo_gif/cover_image files onto the storage backend
that default_storage currently resolves to (Supabase S3 in an environment
where SUPABASE_S3_* env vars are set, local filesystem otherwise).

Why this exists: import_exercises_dataset.py writes media through Django's
default_storage abstraction, so any run made without the SUPABASE_S3_* env
vars set (e.g. a plain local dev run) lands the files under local
MEDIA_ROOT/exercises/... only -- they never reach the real bucket used in
production. Re-running the full import just to push already-generated files
is wasteful and, since S3Storage here has file_overwrite=False, would mint
new orphaned keys instead of reusing the existing ones. This command instead
walks the existing Exercise rows and re-saves only the files that are still
missing on the currently-resolved backend.

MUST be run in an environment where BOTH of these are true at once:
- the local files actually exist on disk (WebApp/media/exercises/...) --
  i.e. run this from the machine where the original local import happened;
- SUPABASE_S3_ENDPOINT/ACCESS_KEY/SECRET_KEY/BUCKET/REGION are set in the
  process env, pointing at the real bucket, AND DATABASE_URL points at the
  same DB whose Exercise rows you're backfilling.

Usage (from WebApp/src, with the prod env vars exported for this one call):
    python manage.py sync_exercise_media_to_storage --dry-run   # count only
    python manage.py sync_exercise_media_to_storage              # actually upload
"""
from pathlib import Path

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.core.management.base import BaseCommand

from domain.workouts.models import Exercise

FIELD_NAMES = ('demo_gif', 'cover_image')


class Command(BaseCommand):
    help = 'Backfill Exercise demo_gif/cover_image files onto the current default_storage backend.'

    def add_arguments(self, parser):
        parser.add_argument('--dry-run', action='store_true', help='Conta soltanto, nessuna scrittura.')

    def handle(self, *args, **options):
        dry_run = options['dry_run']

        if not settings.SUPABASE_S3_ENDPOINT:
            self.stdout.write(self.style.WARNING(
                '>> SUPABASE_S3_ENDPOINT non impostata: default_storage punta al filesystem locale. '
                'Se l\'intento è sincronizzare su Supabase, imposta le env var SUPABASE_S3_* prima di rilanciare.'
            ))
            if not dry_run:
                self.stdout.write(self.style.WARNING('>> Procedo comunque (nessun --dry-run), ma i file finiranno di nuovo in locale.'))

        already_synced = 0
        backfilled = 0
        missing_locally = 0

        for exercise in Exercise.objects.exclude(demo_gif='', cover_image='').iterator():
            for field_name in FIELD_NAMES:
                field = getattr(exercise, field_name)
                if not field:
                    continue

                if default_storage.exists(field.name):
                    already_synced += 1
                    continue

                local_path = Path(settings.MEDIA_ROOT) / field.name
                if not local_path.exists():
                    missing_locally += 1
                    self.stdout.write(self.style.WARNING(
                        f'   [{exercise.dataset_id or exercise.id}] {field_name}: file locale mancante ({local_path}), saltato.'
                    ))
                    continue

                backfilled += 1
                if dry_run:
                    self.stdout.write(f'   [{exercise.dataset_id or exercise.id}] {field_name}: da sincronizzare ({field.name}).')
                    continue

                content = ContentFile(local_path.read_bytes())
                field.save(local_path.name, content, save=True)
                self.stdout.write(f'   [{exercise.dataset_id or exercise.id}] {field_name}: sincronizzato.')

        mode = 'DRY-RUN' if dry_run else 'completato'
        self.stdout.write(self.style.SUCCESS(
            f'== {mode}. Già sincronizzati: {already_synced}  |  '
            f'{"Da sincronizzare" if dry_run else "Sincronizzati"}: {backfilled}  |  '
            f'Mancanti su disco: {missing_locally}'
        ))
