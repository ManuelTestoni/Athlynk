"""Misurazione singola → QuestionnaireResponse leggera, visibile in grafico,
storico e percorso. Copre helper + endpoint mobile (atleta e coach)."""
import json
from datetime import date, timedelta

from django.contrib.auth.hashers import make_password
from django.test import TestCase

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.coaching.models import CoachingRelationship
from domain.checks.models import QuestionnaireResponse

from .views_check.helpers import create_quick_measurement, QuickMeasurementError, _build_chart_data
from .views_client import _build_percorso_events


def _coach_and_client():
    cu = User.objects.create(email='c@e.com', password_hash=make_password('x'),
                             role='COACH', is_verified=True)
    coach = CoachProfile.objects.create(
        user=cu, first_name='Pro', last_name='Coach',
        professional_type='COACH', platform_subscription_status='ACTIVE')
    au = User.objects.create(email='a@e.com', password_hash=make_password('x'),
                             role='CLIENT', is_verified=True)
    client = ClientProfile.objects.create(user=au, first_name='Mario', last_name='Rossi')
    CoachingRelationship.objects.create(
        coach=coach, client=client, status='ACTIVE',
        start_date=date.today() - timedelta(days=30), relationship_type='FULL')
    return coach, client


class CreateQuickMeasurementTests(TestCase):
    def setUp(self):
        self.coach, self.client_p = _coach_and_client()

    def test_weight_appears_in_chart_and_percorso(self):
        day = date.today() - timedelta(days=3)
        r = create_quick_measurement(self.coach, self.client_p, 'weight', None, 80.5, day)
        self.assertEqual(float(r.weight_kg), 80.5)
        self.assertEqual(r.status, 'REVIEWED')
        self.assertEqual(r.submitted_at.date(), day)

        chart = _build_chart_data(self.client_p)
        self.assertIn(80.5, chart['weight'])

        events = _build_percorso_events(
            self.client_p, self.coach,
            date.today() - timedelta(days=365), date.today())
        kinds = [(e['type'], e['title']) for e in events]
        self.assertIn(('check', 'Misurazione rapida'), kinds)

    def test_circumference_and_skinfold(self):
        day = date.today()
        rc = create_quick_measurement(self.coach, self.client_p, 'circumference', 'waist', 82.0, day)
        self.assertEqual(rc.body_circumferences.get('waist'), '82.0')
        rs = create_quick_measurement(self.coach, self.client_p, 'skinfold', 'triceps', 12.0, day)
        self.assertEqual(rs.skinfolds.get('triceps'), '12.0')

    def test_one_synthetic_template_reused(self):
        create_quick_measurement(self.coach, self.client_p, 'weight', None, 80.0, date.today())
        create_quick_measurement(self.coach, self.client_p, 'weight', None, 79.0, date.today())
        tids = set(QuestionnaireResponse.objects.filter(coach=self.coach)
                   .values_list('questionnaire_template_id', flat=True))
        self.assertEqual(len(tids), 1)

    def test_out_of_range_rejected(self):
        with self.assertRaises(QuickMeasurementError):
            create_quick_measurement(self.coach, self.client_p, 'weight', None, 5.0, date.today())
        with self.assertRaises(QuickMeasurementError):
            create_quick_measurement(self.coach, self.client_p, 'circumference', 'waist', 9.0, date.today())

    def test_future_date_rejected(self):
        with self.assertRaises(QuickMeasurementError):
            create_quick_measurement(self.coach, self.client_p, 'weight', None, 80.0,
                                     date.today() + timedelta(days=1))


class MeasurementEndpointTests(TestCase):
    def setUp(self):
        self.coach, self.client_p = _coach_and_client()

    def _athlete_session(self):
        s = self.client.session
        s['user_id'] = self.client_p.user.id
        s['user_role'] = 'CLIENT'
        s.save()

    def _coach_session(self):
        s = self.client.session
        s['user_id'] = self.coach.user.id
        s['user_role'] = 'COACH'
        s.save()

    def test_athlete_web_endpoint(self):
        self._athlete_session()
        resp = self.client.post(
            '/api/cliente/misurazione/',
            data=json.dumps({'type': 'weight', 'value': 77.0,
                             'date': date.today().isoformat()}),
            content_type='application/json')
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(QuestionnaireResponse.objects.filter(client=self.client_p).exists())

    def test_coach_web_endpoint(self):
        self._coach_session()
        resp = self.client.post(
            f'/api/coach/clienti/{self.client_p.id}/misurazione/',
            data=json.dumps({'type': 'circumference', 'key': 'waist', 'value': 81.0,
                             'date': date.today().isoformat()}),
            content_type='application/json')
        self.assertEqual(resp.status_code, 200)
        r = QuestionnaireResponse.objects.get(client=self.client_p)
        self.assertEqual(r.body_circumferences.get('waist'), '81.0')


class MeasurementPartialRenderTests(TestCase):
    def test_partial_renders(self):
        from django.template.loader import render_to_string
        from domain.checks.anthropometry import measurement_options
        html = render_to_string('partials/_add_measurement.html', {
            'measurement_options_json': json.dumps(measurement_options()),
            'measurement_post_url': '/api/cliente/misurazione/',
        })
        self.assertIn('Aggiungi misurazione', html)
        self.assertIn('addMeasurement(', html)

