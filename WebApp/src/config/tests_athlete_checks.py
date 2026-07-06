"""Storico check lato atleta (app iOS): dettaglio di un check compilato,
incluso il riepilogo dello strumento «Calcolo Fabbisogni»."""
import json
from datetime import date, timedelta

from django.contrib.auth.hashers import make_password
from django.test import TestCase, override_settings
from django.utils import timezone

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.coaching.models import CoachingRelationship
from domain.checks.models import QuestionnaireTemplate, QuestionnaireResponse
from .api import issue_token

LOCMEM = {'default': {'BACKEND': 'django.core.cache.backends.locmem.LocMemCache'}}

QUESTIONS = [
    {'id': 'umore', 'type': 'media', 'label': 'Umore', 'step_id': 's1', 'min': 1, 'max': 5},
    {'id': 'tool_fabbisogni', 'type': 'strumento_fabbisogni', 'label': 'Calcolo Fabbisogni', 'step_id': 's2'},
]
STEPS = [{'id': 's1', 'label': 'Check'}, {'id': 's2', 'label': 'Fabbisogni'}]


@override_settings(CACHES=LOCMEM)
class AthleteCheckDetailTests(TestCase):
    def setUp(self):
        cu = User.objects.create(email='coach2@e.com', password_hash=make_password('x'),
                                  role='COACH', is_verified=True)
        self.coach = CoachProfile.objects.create(
            user=cu, first_name='Pro', last_name='Coach',
            professional_type='COACH', platform_subscription_status='ACTIVE')
        au = User.objects.create(email='ath2@e.com', password_hash=make_password('x'),
                                  role='CLIENT', is_verified=True)
        self.client_p = ClientProfile.objects.create(user=au, first_name='Mario', last_name='Rossi')
        CoachingRelationship.objects.create(
            coach=self.coach, client=self.client_p, status='ACTIVE',
            start_date=date.today(), relationship_type='FULL')
        self.h = {'HTTP_AUTHORIZATION': f'Bearer {issue_token(au)}'}

        self.template = QuestionnaireTemplate.objects.create(
            coach=self.coach, title='Anamnesi', questionnaire_type='CUSTOM',
            questions_config=QUESTIONS, steps_config=STEPS)
        self.response = QuestionnaireResponse.objects.create(
            coach=self.coach, client=self.client_p, questionnaire_template=self.template,
            questions_snapshot=QUESTIONS, steps_snapshot=STEPS,
            submitted_at=timezone.now(),
            answers_json={
                'umore': 4,
                'altezza_cm': 180, 'peso_kg': 80, 'eta_anni': 30, 'sesso': 'Maschio',
                'formula_mb': 'Mifflin-St Jeor', 'mb_stimata_kcal': 1780,
                'pal_valore': 1.55, 'det_kcal': 2759, 'det_adjust_kcal': -200,
                'det_finale_kcal': 2559,
                'proteine_gkg': 2, 'proteine_g_totale': 160,
            },
        )

    def test_detail_includes_generic_and_fabbisogni_sections(self):
        r = self.client.get(f'/api/v1/checks/{self.response.id}', **self.h)
        self.assertEqual(r.status_code, 200)
        data = r.json()
        self.assertEqual(data['title'], 'Anamnesi')
        sections = data['sections']
        by_id = {s['id']: s for s in sections}
        self.assertIn('s1', by_id)
        self.assertIn('s2', by_id)

        umore_q = by_id['s1']['questions'][0]
        self.assertEqual(umore_q['type'], 'media')
        self.assertEqual(umore_q['value'], 4)

        fb_q = by_id['s2']['questions'][0]
        self.assertEqual(fb_q['type'], 'strumento_fabbisogni')
        self.assertEqual(fb_q['fb']['det_finale'], 2559)
        self.assertEqual(fb_q['fb']['macros'][0]['label'], 'Proteine')
        self.assertEqual(fb_q['fb']['macros'][0]['g'], 160)

    def test_other_athletes_check_is_not_visible(self):
        # A second athlete with their OWN active relationship (so the request clears
        # the generic access gate) must still not be able to read someone else's check.
        other_coach_u = User.objects.create(email='coach3@e.com', password_hash=make_password('x'),
                                             role='COACH', is_verified=True)
        other_coach = CoachProfile.objects.create(
            user=other_coach_u, first_name='Altro', last_name='Coach',
            professional_type='COACH', platform_subscription_status='ACTIVE')
        other_u = User.objects.create(email='other@e.com', password_hash=make_password('x'),
                                       role='CLIENT', is_verified=True)
        other_client = ClientProfile.objects.create(user=other_u, first_name='Altro', last_name='Atleta')
        CoachingRelationship.objects.create(
            coach=other_coach, client=other_client, status='ACTIVE',
            start_date=date.today(), relationship_type='FULL')
        h = {'HTTP_AUTHORIZATION': f'Bearer {issue_token(other_u)}'}
        r = self.client.get(f'/api/v1/checks/{self.response.id}', **h)
        self.assertEqual(r.status_code, 404)
