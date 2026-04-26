from django.core.management.base import BaseCommand
from domain.accounts.models import CoachProfile, ClientProfile
from domain.checks.models import QuestionnaireTemplate, QuestionnaireResponse, ProgressPhoto
from django.utils import timezone

class Command(BaseCommand):
    help = 'Popola il database con dati iniziali per checks (Template Questionario, Risposta e Foto Profilo)'

    def handle(self, *args, **kwargs):
        self.stdout.write('Inizio seeding dei check-in...')

        # 0. Recupero account
        coach = CoachProfile.objects.first()
        client = ClientProfile.objects.first()

        if not coach or not client:
            self.stdout.write(self.style.ERROR('Errore: Devi prima popolare gli account. Esegui "python manage.py seed_accounts"'))
            return

        # 1. Creazione del Template del Questionario Periodico
        template, created_template = QuestionnaireTemplate.objects.get_or_create(
            coach=coach,
            title='Check-in Settimanale Standard',
            defaults={
                'description': 'Questionario per valutare l\'andamento della settimana',
                'questionnaire_type': 'WEEKLY_CHECK',
                'frequency_type': 'WEEKLY',
                'objective': 'Monitoraggio generale'
            }
        )

        # 2. Creazione della Risposta al Questionario da parte del Client
        response, created_response = QuestionnaireResponse.objects.get_or_create(
            questionnaire_template=template,
            client=client,
            coach=coach,
            defaults={
                'submitted_at': timezone.now(),
                'status': 'SUBMITTED',
                'weight_kg': 75.1,  # Un leggero dimagrimento rispetto ai 75.5 dell'anamnesi iniziale
                'body_circumferences': {
                    'vita': 82.5,
                    'fianchi': 95.0,
                    'braccio_dx': 34.0,
                    'braccio_sx': 33.5
                },
                'notes': 'Settimana andata bene, buon pump nel workout Upper focus.',
                'answers_json': {
                    'livello_energia': 8,
                    'aderenza_dieta': '90%',
                    'dolori': 'Nessuno, la spalla ha retto bene.'
                }
            }
        )

        # 3. Creazione di una Foto Progressi allegata al check-in
        photo, created_photo = ProgressPhoto.objects.get_or_create(
            client=client,
            coach=coach,
            questionnaire_response=response,
            photo_type='FRONT',
            defaults={
                'file_url': 'https://placehold.co/400x800/png?text=Frontale', # URL immagine fittizia
                'captured_at': timezone.now(),
                'notes': 'Condizione a digiuno al mattino'
            }
        )

        self.stdout.write(self.style.SUCCESS(f'Creato con successo! Template Questionario e una Risposta compilata (con Foto Frontale) per {client.first_name}.'))

