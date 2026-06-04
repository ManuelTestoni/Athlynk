"""Management command: send 23:00 reminder emails to clients whose macro log
for today is incomplete. Run this daily at 23:00 via cron:

    python manage.py send_macro_reminders

A client is considered incomplete if:
- They have a DAILY plan: total logged kcal < 80% of target, OR no entries at all.
- They have a WEEKLY plan: total logged kcal for today's weekday < 80% of target, OR no entries.
If no kcal target is set, we skip (nothing to remind about).
"""
import calendar
from datetime import date

from django.conf import settings
from django.core.management.base import BaseCommand
from django.urls import reverse

from domain.nutrition.models import NutritionAssignment, ClientMacroLogEntry
from domain.chat.models import Notification


COMPLETION_THRESHOLD = 0.80


class Command(BaseCommand):
    help = 'Send macro reminder emails to clients with incomplete food logs today.'

    def handle(self, *args, **options):
        from config.services.email import send_macro_reminder

        today = date.today()
        today_dow = calendar.day_name[today.weekday()].upper()  # e.g. 'MONDAY'

        assignments = (
            NutritionAssignment.objects
            .filter(status='ACTIVE', nutrition_plan__plan_mode='MACRO')
            .select_related('nutrition_plan', 'client__user')
        )

        sent = 0
        pushed = 0
        for assignment in assignments:
            plan = assignment.nutrition_plan
            target_kcal = self._get_target_kcal(plan, today_dow)
            if not target_kcal:
                continue

            today_entries = list(
                ClientMacroLogEntry.objects
                .filter(assignment=assignment, log_date=today)
                .select_related('food')
            )
            total_kcal = sum(
                (e.food.energia_kcal * e.quantity_g / 100 if e.food else 0)
                for e in today_entries
            )

            if total_kcal >= target_kcal * COMPLETION_THRESHOLD:
                continue

            client = assignment.client
            plan_url = (
                f"{settings.SITE_URL}"
                f"{reverse('nutrizione_client_detail', args=[assignment.id])}"
            )
            ok = send_macro_reminder(client, plan, plan_url)
            if ok:
                sent += 1
                if options.get('verbosity', 1) >= 2:
                    self.stdout.write(f'  Sent to {client}')

            # In-app + push reminder. Creating the Notification fires an APNs push
            # via the post_save signal (a no-op until APNs keys are configured).
            # Deduped to one MACRO_REMINDER per client per day.
            pushed += self._push_reminder(client, today)

        self.stdout.write(self.style.SUCCESS(
            f'Sent {sent} macro reminder email(s); {pushed} in-app/push reminder(s).'
        ))

    def _push_reminder(self, client, today):
        user = getattr(client, 'user', None)
        if not user:
            return 0
        if Notification.objects.filter(
            target_user=user, notification_type='MACRO_REMINDER', created_at__date=today
        ).exists():
            return 0
        Notification.objects.create(
            target_user=user,
            notification_type='MACRO_REMINDER',
            title='Completa i macro di oggi',
            body='Registra gli alimenti prima di mezzanotte: a fine giornata il diario viene chiuso.',
            link_url='/nutrizione/',
        )
        return 1

    def _get_target_kcal(self, plan, today_dow):
        if plan.plan_kind == 'DAILY':
            return plan.daily_kcal or 0
        # WEEKLY: find the DietDay for today
        day = plan.days.filter(day_of_week=today_dow).first()
        return (day.target_kcal or 0) if day else 0
