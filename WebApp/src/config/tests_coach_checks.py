"""Gestione check coach via API mobile: modelli (CRUD), assegnazione,
compilazione per atleta, modifica valori. Parità con la web app."""
import json
from datetime import date

from django.contrib.auth.hashers import make_password
from django.test import TestCase, override_settings

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.coaching.models import CoachingRelationship
from domain.checks.models import (
    QuestionnaireTemplate, QuestionnaireResponse, AssignedCheck, AssignedCheckInstance,
)
from .api import issue_token

LOCMEM = {'default': {'BACKEND': 'django.core.cache.backends.locmem.LocMemCache'}}

ANTHRO_Q = {
    'id': 'antropometria', 'type': 'antropometria', 'label': 'Misure',
    'step_id': 's1', 'weight': True, 'circumferences': ['waist'], 'skinfolds': ['triceps'],
}


@override_settings(CACHES=LOCMEM)
class CoachCheckManagementTests(TestCase):
    def setUp(self):
        u = User.objects.create(email='coach@e.com', password_hash=make_password('x'),
                                role='COACH', is_verified=True)
        self.coach = CoachProfile.objects.create(
            user=u, first_name='Pro', last_name='Coach',
            professional_type='COACH', platform_subscription_status='ACTIVE')
        au = User.objects.create(email='ath@e.com', password_hash=make_password('x'),
                                 role='CLIENT', is_verified=True)
        self.client_p = ClientProfile.objects.create(user=au, first_name='Mario', last_name='Rossi')
        CoachingRelationship.objects.create(
            coach=self.coach, client=self.client_p, status='ACTIVE',
            start_date=date.today(), relationship_type='FULL')
        self.h = {'HTTP_AUTHORIZATION': f'Bearer {issue_token(u)}'}

    def _post(self, path, payload):
        return self.client.post(path, data=json.dumps(payload),
                                content_type='application/json', **self.h)

    def test_list_includes_presets(self):
        resp = self.client.get('/api/v1/coach/check-templates', **self.h)
        self.assertEqual(resp.status_code, 200)
        self.assertGreaterEqual(len(resp.json()['presets']), 1)

    def test_create_update_duplicate_delete(self):
        r = self._post('/api/v1/coach/check-templates/create',
                       {'title': 'Custom', 'steps_config': [{'id': 's1', 'label': 'Step'}],
                        'questions_config': [ANTHRO_Q]})
        self.assertEqual(r.status_code, 201)
        tid = r.json()['id']

        ru = self.client.post(f'/api/v1/coach/check-templates/{tid}/update',
                              data=json.dumps({'title': 'Rinominato'}),
                              content_type='application/json', **self.h)
        self.assertEqual(ru.status_code, 200)
        self.assertEqual(QuestionnaireTemplate.objects.get(id=tid).title, 'Rinominato')

        rd = self._post(f'/api/v1/coach/check-templates/{tid}/duplicate', {})
        self.assertEqual(rd.status_code, 201)

        rx = self._post(f'/api/v1/coach/check-templates/{tid}/delete', {})
        self.assertEqual(rx.status_code, 200)
        self.assertFalse(QuestionnaireTemplate.objects.get(id=tid).is_active)

    def test_assign_creates_instance(self):
        tid = self._post('/api/v1/coach/check-templates/create',
                         {'title': 'T', 'questions_config': [ANTHRO_Q]}).json()['id']
        r = self._post(f'/api/v1/coach/check-templates/{tid}/assign',
                       {'client_id': self.client_p.id, 'recurrence_type': 'once'})
        self.assertEqual(r.status_code, 200)
        self.assertTrue(AssignedCheck.objects.filter(client=self.client_p).exists())
        self.assertTrue(AssignedCheckInstance.objects.filter(
            assignment__client=self.client_p, status='pending').exists())

    def test_fill_then_edit_values(self):
        tid = self._post('/api/v1/coach/check-templates/create',
                         {'title': 'T', 'questions_config': [ANTHRO_Q]}).json()['id']
        rf = self._post(f'/api/v1/coach/check-templates/{tid}/fill', {
            'client_id': self.client_p.id,
            'answers': {'peso_corporeo': 80, 'circ::waist': 82, 'pl::triceps': 12},
            'date': date.today().isoformat(),
        })
        self.assertEqual(rf.status_code, 201)
        rid = rf.json()['id']
        resp = QuestionnaireResponse.objects.get(id=rid)
        self.assertEqual(float(resp.weight_kg), 80.0)
        self.assertEqual(resp.status, 'REVIEWED')
        self.assertEqual(resp.body_circumferences.get('waist'), '82.0')

        before_submit = resp.submitted_at
        re = self.client.post(f'/api/v1/coach/checks/{rid}/values/update',
                              data=json.dumps({'answers': {'peso_corporeo': 79, 'circ::waist': 81}}),
                              content_type='application/json', **self.h)
        self.assertEqual(re.status_code, 200)
        resp.refresh_from_db()
        self.assertEqual(float(resp.weight_kg), 79.0)
        self.assertEqual(resp.submitted_at, before_submit)  # date anchor unchanged

    def test_prefill_endpoint(self):
        tid = self._post('/api/v1/coach/check-templates/create',
                         {'title': 'T', 'questions_config': [ANTHRO_Q]}).json()['id']
        rid = self._post(f'/api/v1/coach/check-templates/{tid}/fill', {
            'client_id': self.client_p.id,
            'answers': {'peso_corporeo': 80},
        }).json()['id']
        r = self.client.get(f'/api/v1/coach/checks/{rid}/values', **self.h)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()['prefill'].get('peso_corporeo'), 80.0)
