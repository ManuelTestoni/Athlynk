from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from domain.billing.models import ClientSubscription
from domain.chat.services import send_automatic_message


class Command(BaseCommand):
    help = "Send the SUBSCRIPTION_EXPIRING automatic message for subscriptions ending soon. Idempotent."

    def add_arguments(self, parser):
        parser.add_argument('--days', type=int, default=7, help='Days before end_date to notify (default 7).')

    def handle(self, *args, **options):
        days = options['days']
        today = timezone.now().date()
        cutoff = today + timedelta(days=days)

        subs = (
            ClientSubscription.objects
            .filter(status='ACTIVE', expiry_reminder_sent=False,
                    end_date__isnull=False, end_date__gte=today, end_date__lte=cutoff)
            .select_related('client', 'client__user', 'subscription_plan', 'subscription_plan__coach', 'subscription_plan__coach__user')
        )

        sent = 0
        for sub in subs:
            coach = sub.subscription_plan.coach
            client = sub.client
            send_automatic_message(coach, client, 'SUBSCRIPTION_EXPIRING')
            sub.expiry_reminder_sent = True
            sub.save(update_fields=['expiry_reminder_sent', 'updated_at'])
            sent += 1

        self.stdout.write(self.style.SUCCESS(f'Expiry reminders processed: {sent}'))
