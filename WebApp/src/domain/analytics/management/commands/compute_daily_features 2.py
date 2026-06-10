from django.core.management.base import BaseCommand
from django.utils import timezone
from django.utils.dateparse import parse_date

from domain.analytics.services import features


class Command(BaseCommand):
    help = "Build the DailyFeatureStore rows for a snapshot date (default today)."

    def add_arguments(self, parser):
        parser.add_argument('--date', type=str, default=None, help='YYYY-MM-DD (default today).')
        parser.add_argument('--no-enrich', action='store_true', help='Skip PostHog enrichment.')

    def handle(self, *args, **options):
        snapshot = parse_date(options['date']) if options['date'] else timezone.now().date()
        written = features.build_and_store(snapshot, enrich=not options['no_enrich'])
        self.stdout.write(self.style.SUCCESS(f'Feature rows written for {snapshot}: {written}'))
