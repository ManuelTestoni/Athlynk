from django.core.management.base import BaseCommand
from domain.accounts.models import CoachProfile
from domain.checks.models import CheckFolder, QuestionnaireTemplate
from domain.checks.preset_templates import PRESETS


class Command(BaseCommand):
    help = "One-off backfill: move existing preset check templates into each coach's 'Template' folder."

    def handle(self, *args, **opts):
        assigned = 0
        for coach in CoachProfile.objects.all():
            folder, _ = CheckFolder.objects.get_or_create(coach=coach, title='Template')
            assigned += QuestionnaireTemplate.objects.filter(
                coach=coach, preset_key__in=list(PRESETS.keys()), folder__isnull=True,
            ).update(folder=folder)
        self.stdout.write(self.style.SUCCESS(f'Assegnata cartella "Template" a {assigned} preset esistenti.'))
