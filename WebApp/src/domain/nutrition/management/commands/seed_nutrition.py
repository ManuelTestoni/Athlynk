from django.core.management.base import BaseCommand
from domain.accounts.models import CoachProfile, ClientProfile
from domain.nutrition.models import NutritionPlan, NutritionAssignment
from datetime import date

class Command(BaseCommand):
    help = 'Popola il database con dati iniziali per nutrition (Piano Nutrizionale, Assegnazione)'

    def handle(self, *args, **kwargs):
        self.stdout.write('Inizio seeding della nutrizione...')

        # 0. Recupero account
        coach = CoachProfile.objects.first()
        client = ClientProfile.objects.first()

        if not coach or not client:
            self.stdout.write(self.style.ERROR('Errore: Devi prima popolare gli account. Esegui "python manage.py seed_accounts"'))
            return

        # 1. Creazione di un Piano Nutrizionale
        plan, created_plan = NutritionPlan.objects.get_or_create(
            coach=coach,
            title='Piano Ricomposizione Corporea',
            defaults={
                'description': 'Piano bilanciato con focus su un moderato deficit calorico e mantenimento del muscolo.',
                'plan_type': 'Flessibile',
                'nutrition_goal': 'Ricomposizione / Adattamento',
                'daily_kcal': 2200,
                'protein_target_g': 160,
                'carb_target_g': 220,
                'fat_target_g': 75,
                'meals_per_day': 4,
                'status': 'PUBLISHED',
                'is_template': False
            }
        )

        # 2. Assegnazione del Piano al Cliente
        assignment, _ = NutritionAssignment.objects.get_or_create(
            nutrition_plan=plan,
            client=client,
            coach=coach,
            defaults={
                'status': 'ACTIVE',
                'start_date': date.today(),
                'notes': 'Seguire il piano possibilmente basandosi su 4 pasti. Acqua raccomandata: 3 litri.',
            }
        )

        self.stdout.write(self.style.SUCCESS(f'Creato con successo! 1 Piano Nutrizionale ({plan.title}) assegnato a {client.first_name}.'))

