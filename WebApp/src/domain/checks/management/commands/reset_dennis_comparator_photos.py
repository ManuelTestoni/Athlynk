"""One-off: Dennis Ciuffo's comparator photos were seeded with fake/placeholder
file_url values that don't point at anything in the Supabase bucket. Delete
them and replace with 2 real webp uploads so the comparator has something to
actually compare.

Usage: python manage.py reset_dennis_comparator_photos /path/to/1.webp /path/to/2.webp
"""
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from domain.accounts.models import ClientProfile
from domain.checks.models import ProgressPhoto


class Command(BaseCommand):
    help = "Delete Dennis Ciuffo's stale comparator photos and seed 2 real webp test photos."

    def add_arguments(self, parser):
        parser.add_argument('image1')
        parser.add_argument('image2')

    def handle(self, *args, **opts):
        client = ClientProfile.objects.filter(last_name__icontains='Ciuffo').first()
        if not client:
            raise CommandError('Client "Ciuffo" not found')

        existing = ProgressPhoto.objects.filter(client=client)
        self.stdout.write(f'Deleting {existing.count()} stale photo(s) for {client}')
        coach = None
        first = existing.first()
        if first:
            coach = first.coach
        existing.delete()

        if coach is None:
            from domain.coaching.models import CoachingRelationship
            rel = CoachingRelationship.objects.filter(client=client, status='ACTIVE').first()
            if not rel:
                raise CommandError('No coach found to attribute test photos to')
            coach = rel.coach

        now = timezone.now()
        for i, (path, label, days_ago) in enumerate([(opts['image1'], 'TEST 1', 30), (opts['image2'], 'TEST 2', 0)]):
            with open(path, 'rb') as f:
                saved_name = default_storage.save(f'progress_photos/{client.id}/test_{i}.webp', ContentFile(f.read()))
            ProgressPhoto.objects.create(
                client=client,
                coach=coach,
                file_url=default_storage.url(saved_name),
                photo_type='FRONT',
                captured_at=now - timezone.timedelta(days=days_ago),
                notes=f'{label} — immagine di prova per verifica comparatore',
            )
            self.stdout.write(self.style.SUCCESS(f'Created photo from {path}'))
