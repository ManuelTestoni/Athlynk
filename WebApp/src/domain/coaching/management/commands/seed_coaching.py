from django.core.management.base import BaseCommand
from domain.accounts.models import CoachProfile, ClientProfile
from domain.coaching.models import CoachingRelationship, ClientAnamnesis
from datetime import date

class Command(BaseCommand):
    help = 'Popola il database con dati iniziali per coaching (Relazione Coach-Cliente, Anamnesi)'

    def handle(self, *args, **kwargs):
        self.stdout.write('Inizio seeding del coaching...')

        # 0. Recupero account
        coach = CoachProfile.objects.first()
        client = ClientProfile.objects.first()

        if not coach or not client:
            self.stdout.write(self.style.ERROR('Errore: Devi prima popolare gli account. Esegui "python manage.py seed_accounts"'))
            return

        # 1. Creazione della Relazione di Coaching
        relationship, created_rel = CoachingRelationship.objects.get_or_create(
            coach=coach,
            client=client,
            defaults={
                'status': 'ACTIVE',
                'start_date': date.today(),
                'relationship_type': 'Online Coaching Premium',
                'internal_notes': 'Cliente molto motivato, focus su ipertrofia.'
            }
        )

        # 2. Creazione dell'Anamnesi Base del Cliente
        anamnesis, created_anamnesis = ClientAnamnesis.objects.get_or_create(
            client=client,
            coach=coach,
            defaults={
                'anamnesis_date': date.today(),
                'age': 28,
                'weight_kg': 75.5,
                'height_cm': 180.0,
                'medical_history': 'Nessuna patologia rilevante.',
                'injuries': 'Lieve fastidio pre-gresso spalla sx (cuffia rotatori).',
                'allergies': 'Nessuna allergia alimentare.',
                'sleep_quality': 'Buona, circa 7-8 ore a notte.',
                'stress_level': 'Medio, lavoro d\'ufficio sedentario.',
                'path_goal': 'Aumento massa muscolare mantenendo BF sotto il 15%.',
                'professional_notes': 'Partire con volume moderato su esercizi di spinta verticale per testare la spalla.'
            }
        )

        self.stdout.write(self.style.SUCCESS(f'Creato con successo! Relazione Coaching per {client.first_name} e l\'Anamnesi associata.'))

