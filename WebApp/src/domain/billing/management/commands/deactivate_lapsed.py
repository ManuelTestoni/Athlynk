from django.core.management.base import BaseCommand
from django.utils import timezone

from domain.accounts.models import ClientProfile
from domain.billing.models import ClientSubscription
from config.session_utils import enforce_client_access


class Command(BaseCommand):
    help = (
        "Expire lapsed client subscriptions (status -> EXPIRED). Does not touch "
        "the coaching relationship — a lapsed subscription only re-gates the "
        "specific domain (workout/nutrition) for that athlete, it doesn't block "
        "the app. Idempotent — safe to run on a daily cron."
    )

    def handle(self, *args, **options):
        today = timezone.now().date()
        # Candidates: clients with an ACTIVE subscription already past its end_date.
        # enforce_client_access performs the authoritative per-client sweep.
        client_ids = list(
            ClientSubscription.objects
            .filter(status='ACTIVE', end_date__isnull=False, end_date__lt=today)
            .values_list('client_id', flat=True)
            .distinct()
        )

        expired = 0
        for client in ClientProfile.objects.filter(id__in=client_ids):
            expired += enforce_client_access(client)

        self.stdout.write(self.style.SUCCESS(
            f'Lapsed sweep: {len(client_ids)} clients checked, {expired} subscriptions expired.'
        ))
