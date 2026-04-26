from django.core.management.base import BaseCommand
from domain.accounts.models import CoachProfile, ClientProfile
from domain.calendar.models import Appointment
from django.utils import timezone
from datetime import timedelta

class Command(BaseCommand):
    help = 'Popola il database con dati iniziali per calendar (Appuntamento / Video Call)'

    def handle(self, *args, **kwargs):
        self.stdout.write('Inizio seeding degli appuntamenti...')

        # 0. Recupero account
        coach = CoachProfile.objects.first()
        client = ClientProfile.objects.first()

        if not coach or not client:
            self.stdout.write(self.style.ERROR('Errore: Devi prima popolare gli account. Esegui "python manage.py seed_accounts"'))
            return

        # 1. Creazione di un appuntamento futuro 
        # Imposta un appuntamento per domani alla stessa ora attuale
        start_time = timezone.now() + timedelta(days=1)
        end_time = start_time + timedelta(minutes=45) # 45 minuti di call

        appointment, created_apt = Appointment.objects.get_or_create(
            coach=coach,
            client=client,
            appointment_type='VIDEO_CALL',
            defaults={
                'title': 'Call di Check-in Mensile',
                'description': 'Analizzeremo i risultati dell\'ultimo mese di dieta e variamo la scheda sulle spalle.',
                'start_datetime': start_time,
                'end_datetime': end_time,
                'location': 'Google Meet',
                'meeting_url': 'https://meet.google.com/abc-defg-hij',
                'status': 'SCHEDULED'
            }
        )

        self.stdout.write(self.style.SUCCESS(f'Creato con successo! 1 Appuntamento ({appointment.title}) per {client.first_name} fissato per domani.'))

