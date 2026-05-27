from django.core.management.base import BaseCommand
from domain.accounts.models import CoachProfile
from domain.checks.models import QuestionnaireTemplate
from domain.checks.preset_templates import PRESETS, build_template_payload


class Command(BaseCommand):
    help = 'Clone the 5 system preset templates into one or all coaches (idempotent).'

    def add_arguments(self, parser):
        parser.add_argument('--coach-id', type=int, default=None,
                            help='Limit cloning to the given coach id. If omitted, all coaches.')

    def handle(self, *args, **opts):
        coach_id = opts.get('coach_id')
        coaches = CoachProfile.objects.filter(id=coach_id) if coach_id else CoachProfile.objects.all()
        if not coaches.exists():
            self.stdout.write(self.style.ERROR('Nessun coach trovato.'))
            return

        created = 0
        skipped = 0
        for coach in coaches:
            for key in PRESETS:
                obj, was_created = QuestionnaireTemplate.objects.get_or_create(
                    coach=coach,
                    preset_key=key,
                    defaults=build_template_payload(key),
                )
                if was_created:
                    created += 1
                else:
                    skipped += 1
        self.stdout.write(self.style.SUCCESS(
            f'Preset templates: creati {created}, già presenti {skipped} (coach: {coaches.count()}).'
        ))
