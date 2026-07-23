from django.core.management import call_command
from django.core.management.base import BaseCommand
from django.utils import timezone
from django.utils.dateparse import parse_date


class Command(BaseCommand):
    help = ("Nightly umbrella: compute features -> score risk -> roll up KPIs. "
            "Single cron entry. Add to crontab, e.g.  0 2 * * *  "
            "python manage.py run_daily_analytics")

    def add_arguments(self, parser):
        parser.add_argument('--date', type=str, default=None, help='YYYY-MM-DD (default today).')
        parser.add_argument('--no-enrich', action='store_true', help='Skip PostHog enrichment.')

    def handle(self, *args, **options):
        snapshot = parse_date(options['date']) if options['date'] else timezone.now().date()
        date_arg = snapshot.isoformat()
        self.stdout.write(f'== Daily analytics for {date_arg} ==')
        feat_kwargs = {'date': date_arg}
        if options['no_enrich']:
            feat_kwargs['no_enrich'] = True
        call_command('compute_daily_features', **feat_kwargs)
        call_command('score_risk', date=date_arg)
        call_command('rollup_coach_metrics', date=date_arg)
        self._prune_import_jobs()
        self.stdout.write(self.style.SUCCESS('Daily analytics complete.'))

    def _prune_import_jobs(self):
        """Import-job rows are transient (status/result for a single import) and
        only need to outlive their cache mirror. Drop anything older than a day."""
        from datetime import timedelta
        from domain.shared.models import ImportJob
        cutoff = timezone.now() - timedelta(days=1)
        deleted, _ = ImportJob.objects.filter(created_at__lt=cutoff).delete()
        if deleted:
            self.stdout.write(f'Pruned {deleted} stale import job(s).')
