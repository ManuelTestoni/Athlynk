from django.core.management.base import BaseCommand
from domain.accounts.models import CoachProfile, ClientProfile
from domain.billing.models import SubscriptionPlan, ClientSubscription
from datetime import date, timedelta

class Command(BaseCommand):
    help = 'Popola il database con dati iniziali per billing (Piani di abbonamento e Sottoscrizioni)'

    def handle(self, *args, **kwargs):
        self.stdout.write('Inizio seeding del billing...')

        # 0. Recupero account
        coach = CoachProfile.objects.first()
        client = ClientProfile.objects.first()

        if not coach or not client:
            self.stdout.write(self.style.ERROR('Errore: Devi prima popolare gli account. Esegui "python manage.py seed_accounts"'))
            return

        # 1. Creazione di un Piano di Abbonamento per il Coach
        plan, created_plan = SubscriptionPlan.objects.get_or_create(
            coach=coach,
            name='Coaching Premium Trimestrale',
            defaults={
                'plan_type': 'RECURRING',
                'description': 'Abbonamento trimestrale comprensivo di scheda, dieta e 1 videocall mensile.',
                'price': 150.00,
                'currency': 'EUR',
                'duration_days': 90,
                'billing_interval': 'QUARTERLY',
                'included_services': ['Scheda Allenamento', 'Dieta', 'Video Call', 'Supporto WhatsApp'],
                'is_active': True
            }
        )

        # 2. Assegnazione Sottoscrizione al Cliente
        start_date = date.today()
        end_date = start_date + timedelta(days=90)

        subscription, created_sub = ClientSubscription.objects.get_or_create(
            client=client,
            subscription_plan=plan,
            defaults={
                'status': 'ACTIVE',
                'payment_status': 'PAID',
                'start_date': start_date,
                'end_date': end_date,
                'auto_renew': True,
                'external_payment_provider': 'STRIPE',
                'external_reference': 'ch_1Fxyz1234567890'
            }
        )

        self.stdout.write(self.style.SUCCESS(f'Creato con successo! 1 Piano ({plan.name}) e Sottoscrizione per {client.first_name}.'))

