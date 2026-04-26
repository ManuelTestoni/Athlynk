from django.core.management.base import BaseCommand
from domain.accounts.models import CoachProfile, ClientProfile
from domain.workouts.models import Exercise, WorkoutPlan, WorkoutDay, WorkoutExercise, WorkoutAssignment
from datetime import date

class Command(BaseCommand):
    help = 'Popola il database con dati iniziali per workouts (Esercizi, Piano di allenamento, Assegnazione)'

    def handle(self, *args, **kwargs):
        self.stdout.write('Inizio seeding degli allenamenti...')

        # 0. Recupero account (creati dallo script precedente)
        coach = CoachProfile.objects.first()
        client = ClientProfile.objects.first()

        if not coach or not client:
            self.stdout.write(self.style.ERROR('Errore: Devi prima popolare gli account. Esegui "python manage.py seed_accounts"'))
            return

        # 1. Creazione Esercizi base
        squat, _ = Exercise.objects.get_or_create(
            slug='squat-bilanciere',
            defaults={
                'name': 'Squat con Bilanciere',
                'target_muscles': 'Quadricipiti, Glutei, Core',
                'equipment': 'Bilanciere, Rack',
                'difficulty_level': 'Intermedio'
            }
        )

        panca, _ = Exercise.objects.get_or_create(
            slug='panca-piana',
            defaults={
                'name': 'Panca Piana con Bilanciere',
                'target_muscles': 'Pettorali, Spalle, Tricipiti',
                'equipment': 'Panca, Bilanciere',
                'difficulty_level': 'Intermedio'
            }
        )

        # 2. Creazione di un Piano di Allenamento
        plan, created_plan = WorkoutPlan.objects.get_or_create(
            coach=coach,
            title='Scheda Ipertrofia Base',
            defaults={
                'description': 'Piano standard per iniziare un percorso di ipertrofia a buffer',
                'level': 'Principiante/Intermedio',
                'goal': 'Ipertrofia'
            }
        )

        # 3. Creazione di un Giorno di Allenamento
        day1, _ = WorkoutDay.objects.get_or_create(
            workout_plan=plan,
            day_order=1,
            defaults={
                'day_name': 'Giorno 1',
                'title': 'Lower Body + Push',
                'focus_area': 'Full Body Focus Misto'
            }
        )

        # 4. Creazione Associazione Esercizi-Giorno
        WorkoutExercise.objects.get_or_create(
            workout_day=day1,
            exercise=squat,
            order_index=1,
            defaults={
                'set_count': 4,
                'rep_count': 8,
                'rpe': 7,
                'recovery_seconds': 120,
                'technique_notes': 'Scendere sotto il parallelo'
            }
        )

        WorkoutExercise.objects.get_or_create(
            workout_day=day1,
            exercise=panca,
            order_index=2,
            defaults={
                'set_count': 4,
                'rep_count': 6,
                'rpe': 8,
                'recovery_seconds': 150,
                'technique_notes': 'Fermo al petto di 1 secondo'
            }
        )

        # 5. Assegnazione del Piano al Cliente
        assignment, _ = WorkoutAssignment.objects.get_or_create(
            workout_plan=plan,
            client=client,
            coach=coach,
            defaults={
                'status': 'ACTIVE',
                'start_date': date.today()
            }
        )

        self.stdout.write(self.style.SUCCESS(f'Creato con successo! 2 Esercizi, 1 Piano ({plan.title}) assegnato a {client.first_name}.'))

