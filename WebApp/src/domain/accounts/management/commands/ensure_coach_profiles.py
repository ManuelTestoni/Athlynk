"""
Find COACH users that have no CoachProfile and create one with placeholder data.
Runs automatically on deploy; also safe to re-run manually.

Usage:
    python manage.py ensure_coach_profiles [--dry-run]
"""
from django.core.management.base import BaseCommand

from domain.accounts.models import CoachProfile, User


class Command(BaseCommand):
    help = 'Create missing CoachProfile rows for users with role=COACH'

    def add_arguments(self, parser):
        parser.add_argument('--dry-run', action='store_true',
                            help='Print orphaned users without creating profiles')

    def handle(self, *args, **options):
        dry = options['dry_run']
        orphans = User.objects.filter(role='COACH').exclude(
            id__in=CoachProfile.objects.values_list('user_id', flat=True)
        )
        if not orphans.exists():
            self.stdout.write(self.style.SUCCESS('Nessun utente COACH senza profilo.'))
            return

        for user in orphans:
            name_part = user.email.split('@')[0]
            self.stdout.write(
                f"{'[DRY] ' if dry else ''}Utente id={user.id} email={user.email} — "
                f"{'sarebbe creato' if dry else 'creato'} CoachProfile"
            )
            if not dry:
                CoachProfile.objects.create(
                    user=user,
                    first_name=name_part[:50],
                    last_name='',
                    professional_type='COACH',
                    platform_subscription_status='ACTIVE',
                )

        if not dry:
            self.stdout.write(self.style.SUCCESS(
                f'Creati {orphans.count()} CoachProfile mancanti. '
                'Aggiorna nome/cognome dal pannello admin.'
            ))
