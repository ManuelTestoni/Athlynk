"""Tool athlete_recap: scoping al coach (hostile cases) e forma del payload.

Nessuna chiamata LLM reale nei test: con insights=[] narrative.generate_narrative
ritorna subito senza rete (vedi domain/chiron/recap/narrative.py)."""

import json

from django.contrib.auth.hashers import make_password
from django.test import TestCase
from django.utils import timezone

from chiron.coach_tools import athlete_recap
from domain.accounts.models import ClientProfile, CoachProfile, User
from domain.coaching.models import CoachingRelationship


def _coach(email, first='Marco'):
    user = User.objects.create(email=email, password_hash=make_password('x'),
                                role='COACH', is_verified=True)
    return CoachProfile.objects.create(
        user=user, first_name=first, last_name='Rossi',
        professional_type='COACH', platform_subscription_status='ACTIVE')


def _client_of(coach, email, first='Luca'):
    user = User.objects.create(email=email, password_hash=make_password('x'),
                                role='CLIENT', is_verified=True)
    client = ClientProfile.objects.create(user=user, first_name=first, last_name='Bianchi')
    CoachingRelationship.objects.create(
        coach=coach, client=client, status='ACTIVE',
        start_date=timezone.localdate(), relationship_type='FULL')
    return client


class AthleteRecapToolTests(TestCase):
    def setUp(self):
        self.coach = _coach('coach@e.com')
        self.client_profile = _client_of(self.coach, 'athlete@e.com')
        self.other_coach = _coach('rival@e.com', first='Rival')
        self.other_client = _client_of(self.other_coach, 'theirs@e.com', first='Estraneo')

    def _config(self, coach_id):
        return {"configurable": {"coach_id": coach_id}}

    def test_missing_coach_context_is_refused(self):
        result = json.loads(athlete_recap.invoke(
            {"client_id": self.client_profile.id}, config={"configurable": {}},
        ))
        self.assertFalse(result["ok"])

    def test_cannot_recap_another_coachs_athlete(self):
        result = json.loads(athlete_recap.invoke(
            {"client_id": self.other_client.id}, config=self._config(self.coach.id),
        ))
        self.assertFalse(result["ok"])

    def test_recap_own_athlete_returns_expected_shape(self):
        result = json.loads(athlete_recap.invoke(
            {"client_id": self.client_profile.id}, config=self._config(self.coach.id),
        ))
        self.assertTrue(result["ok"])
        self.assertEqual(result["name"], "Luca Bianchi")
        self.assertIn("narrative", result)
        self.assertIn("insights", result)
        self.assertEqual(result["insights"], [])
        self.assertIsNone(result["direction"])
        self.assertTrue(result["actions"])
        self.assertIn(f"/clienti/{self.client_profile.id}/recap/", result["actions"][0]["url"])
