from django.core.management.base import BaseCommand
from django.utils import timezone

from domain.accounts.models import ClientProfile
from domain.billing.models import ClientSubscription
from config.session_utils import enforce_client_access


class Command(BaseCommand):
    help = (
        "Expire lapsed client subscriptions and deactivate any collaboration left "
        "without a valid subscription, so the athlete loses access until renewed. "
        "Idempotent — safe to run on a daily cron."
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

        deactivated = 0
        for client in ClientProfile.objects.filter(id__in=client_ids):
            deactivated += enforce_client_access(client)

        self.stdout.write(self.style.SUCCESS(
            f'Lapsed sweep: {len(client_ids)} clients checked, {deactivated} collaborations deactivated.'
        ))
