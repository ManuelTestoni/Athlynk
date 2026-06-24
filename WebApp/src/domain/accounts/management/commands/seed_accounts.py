from django.core.management.base import BaseCommand
from domain.accounts.models import User, CoachProfile, ClientProfile
from datetime import date

class Command(BaseCommand):
    help = 'Popola il database con dati iniziali per accounts (1 Coach e 1 Cliente)'

    def handle(self, *args, **kwargs):
        self.stdout.write('Inizio seeding degli account...')

        # 1. Creazione Utente Coach
        coach_user, created_coach_user = User.objects.get_or_create(
            email='coach@trainelite.com',
            defaults={
                'password_hash': 'hashed_password_123',  # Esempio fittizio
                'role': 'COACH',
                'is_verified': True
            }
        )

        # 1.1 Creazione Profilo Coach
        coach_profile, created_coach_prof = CoachProfile.objects.get_or_create(
            user=coach_user,
            defaults={
                'first_name': 'Marco',
                'last_name': 'Rossi',
                'phone': '+39 333 1234567',
                'birth_date': date(1988, 5, 20),
                'specialization': 'Powerlifting & Bodybuilding',
                'platform_subscription_status': 'ACTIVE',
                'is_platform_subscription_active': True
            }
        )

        # 2. Creazione Utente Cliente
        client_user, created_client_user = User.objects.get_or_create(
            email='client@trainelite.com',
            defaults={
                'password_hash': 'hashed_password_456', # Esempio fittizio
                'role': 'CLIENT',
                'is_verified': True
            }
        )

        # 2.1 Creazione Profilo Cliente
        client_profile, created_client_prof = ClientProfile.objects.get_or_create(
            user=client_user,
            defaults={
                'first_name': 'Luca',
                'last_name': 'Bianchi',
                'phone': '+39 333 7654321',
                'birth_date': date(1995, 8, 10),
                'client_status': 'ACTIVE'
            }
        )

        # 3. Creazione Secondo Utente Cliente
        client_user_2, created_client_user_2 = User.objects.get_or_create(
            email='client2@trainelite.com',
            defaults={
                'password_hash': 'hashed_password_789',
                'role': 'CLIENT',
                'is_verified': True
            }
        )

        client_profile_2, created_client_prof_2 = ClientProfile.objects.get_or_create(
            user=client_user_2,
            defaults={
                'first_name': 'Fre',
                'last_name': 'Amorelli',
                'phone': '+39 333 7654321',
                'birth_date': date(1995, 8, 10),
                'client_status': 'ACTIVE'
            }
        )

        if created_coach_prof or created_client_prof or created_client_prof_2:
            self.stdout.write(self.style.SUCCESS(f'Creato con successo! 1 Coach ({coach_profile.first_name}) e 1 Cliente ({client_profile.first_name}).'))
        else:
            self.stdout.write(self.style.WARNING('I dati di test esistono già nel database.'))

