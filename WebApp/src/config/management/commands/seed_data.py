from django.core.management.base import BaseCommand
from accounts.models import User, CoachProfile
from coaching.models import SubscriptionPlan
from workouts.models import WorkoutPlan, Exercise
from nutrition.models import NutritionPlan


class Command(BaseCommand):
    help = 'Popola il database con dati di seed per test'

    def handle(self, *args, **options):
        self.stdout.write(self.style.SUCCESS('Inizio seed del database...'))

        # ===== COACHES =====
        coaches_data = [
            {
                'name': 'Marco Rossi',
                'email': 'marco.rossi@example.com',
                'specialization': 'Strength & Conditioning',
                'bio': 'Specializzato in allenamenti di forza e condizionamento atletico. 10+ anni di esperienza.',
                'profile_image': 'https://via.placeholder.com/200?text=Marco+Rossi',
                'certifications': 'NASM-CPT, ISSA-CES',
                'hourly_rate': 50.00,
            },
            {
                'name': 'Giulia Bianchi',
                'email': 'giulia.bianchi@example.com',
                'specialization': 'Weight Loss & Nutrition',
                'bio': 'Esperta in perdita di peso e nutrizione. Certificata in dietetica applicata.',
                'profile_image': 'https://via.placeholder.com/200?text=Giulia+Bianchi',
                'certifications': 'ISSN-SNS, ACE-CPT',
                'hourly_rate': 55.00,
            },
            {
                'name': 'Federico Verdi',
                'email': 'federico.verdi@example.com',
                'specialization': 'Functional Training',
                'bio': 'Specializzato in allenamento funzionale e mobilità. Trainer certificato CrossFit.',
                'profile_image': 'https://via.placeholder.com/200?text=Federico+Verdi',
                'certifications': 'CrossFit Level 1, FMS',
                'hourly_rate': 60.00,
            },
            {
                'name': 'Elena Neri',
                'email': 'elena.neri@example.com',
                'specialization': 'Pilates & Flexibility',
                'bio': 'Instructor certificata in Pilates e flexibility training. Appassionata di movimento consapevole.',
                'profile_image': 'https://via.placeholder.com/200?text=Elena+Neri',
                'certifications': 'Pilates Certified, Yoga Alliance 200h',
                'hourly_rate': 45.00,
            },
            {
                'name': 'Antonio Rossi',
                'email': 'antonio.rossi@example.com',
                'specialization': 'Endurance & Running',
                'bio': 'Maratoneta professionista e coach per corridori. Specializzato in running performance.',
                'profile_image': 'https://via.placeholder.com/200?text=Antonio+Rossi',
                'certifications': 'USATF, NASM-CPT',
                'hourly_rate': 50.00,
            },
        ]

        coaches = {}
        for coach_data in coaches_data:
            email = coach_data.pop('email')
            name = coach_data.pop('name')
            
            # Crea User per il coach
            user, _ = User.objects.get_or_create(
                email=email,
                defaults={
                    'name': name,
                    'role': 'coach',
                    'is_active': True,
                }
            )
            
            # Crea CoachProfile
            coach_profile, created = CoachProfile.objects.get_or_create(
                user=user,
                defaults=coach_data
            )
            
            coaches[name] = coach_profile
            status = 'Created' if created else 'Already exists'
            self.stdout.write(f'  {status}: Coach {name}')

        # ===== SUBSCRIPTION PLANS =====
        subscription_plans_data = [
            {
                'name': 'Basic',
                'description': 'Piano base con accesso ai programmi standard',
                'price': 29.99,
                'duration_days': 30,
                'max_clients': 20,
            },
            {
                'name': 'Professional',
                'description': 'Piano professionale con accesso completo',
                'price': 79.99,
                'duration_days': 30,
                'max_clients': 50,
            },
            {
                'name': 'Premium',
                'description': 'Piano premium con supporto 24/7',
                'price': 149.99,
                'duration_days': 30,
                'max_clients': 100,
            },
        ]

        for plan_data in subscription_plans_data:
            plan, created = SubscriptionPlan.objects.get_or_create(
                name=plan_data['name'],
                defaults=plan_data
            )
            status = 'Created' if created else 'Already exists'
            self.stdout.write(f'  {status}: Subscription Plan {plan_data["name"]}')

        # ===== EXERCISES =====
        exercises_data = [
            {'name': 'Squats', 'description': 'Bodyweight squat', 'muscle_group': 'legs'},
            {'name': 'Push-ups', 'description': 'Standard push-ups', 'muscle_group': 'chest'},
            {'name': 'Pull-ups', 'description': 'Lat pull-ups', 'muscle_group': 'back'},
            {'name': 'Deadlift', 'description': 'Conventional deadlift', 'muscle_group': 'back'},
            {'name': 'Bench Press', 'description': 'Barbell bench press', 'muscle_group': 'chest'},
            {'name': 'Plank', 'description': 'Core plank hold', 'muscle_group': 'core'},
            {'name': 'Lunges', 'description': 'Walking lunges', 'muscle_group': 'legs'},
            {'name': 'Dips', 'description': 'Bodyweight dips', 'muscle_group': 'chest'},
            {'name': 'Mountain Climbers', 'description': 'Dynamic core exercise', 'muscle_group': 'core'},
            {'name': 'Burpees', 'description': 'Full body explosive move', 'muscle_group': 'full_body'},
        ]

        exercises = {}
        for ex_data in exercises_data:
            exercise, created = Exercise.objects.get_or_create(
                name=ex_data['name'],
                defaults=ex_data
            )
            exercises[ex_data['name']] = exercise
            status = 'Created' if created else 'Already exists'
            self.stdout.write(f'  {status}: Exercise {ex_data["name"]}')

        # ===== WORKOUT PLANS =====
        workout_plans_data = [
            {
                'name': 'Strength Foundation',
                'description': 'Programma base per sviluppo della forza',
                'duration_weeks': 12,
                'difficulty': 'beginner',
            },
            {
                'name': 'Fat Loss Cardio',
                'description': 'Programma ad alta intensità per perdita di peso',
                'duration_weeks': 8,
                'difficulty': 'intermediate',
            },
            {
                'name': 'Advanced Strength',
                'description': 'Programma avanzato di forza e potenza',
                'duration_weeks': 16,
                'difficulty': 'advanced',
            },
        ]

        for plan_data in workout_plans_data:
            plan, created = WorkoutPlan.objects.get_or_create(
                name=plan_data['name'],
                defaults=plan_data
            )
            status = 'Created' if created else 'Already exists'
            self.stdout.write(f'  {status}: Workout Plan {plan_data["name"]}')

        # ===== NUTRITION PLANS =====
        nutrition_plans_data = [
            {
                'name': 'Mediterranean Diet',
                'description': 'Dieta mediterranea equilibrata',
                'calories_target': 2000,
                'protein_grams': 150,
                'carbs_grams': 200,
                'fats_grams': 65,
            },
            {
                'name': 'High Protein',
                'description': 'Piano ad alto contenuto proteico per massa muscolare',
                'calories_target': 2500,
                'protein_grams': 200,
                'carbs_grams': 250,
                'fats_grams': 80,
            },
            {
                'name': 'Low Carb',
                'description': 'Piano a basso contenuto di carboidrati',
                'calories_target': 1800,
                'protein_grams': 160,
                'carbs_grams': 120,
                'fats_grams': 70,
            },
        ]

        for plan_data in nutrition_plans_data:
            plan, created = NutritionPlan.objects.get_or_create(
                name=plan_data['name'],
                defaults=plan_data
            )
            status = 'Created' if created else 'Already exists'
            self.stdout.write(f'  {status}: Nutrition Plan {plan_data["name"]}')

        self.stdout.write(self.style.SUCCESS('✅ Seed completato con successo!'))
