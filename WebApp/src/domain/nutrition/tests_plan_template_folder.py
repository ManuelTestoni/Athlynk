"""Saving a nutrition plan as a template must route it into the coach's
default 'Template' folder — mirrors the workout wizard's
finalize(action='template'). See [[project_per_set_overrides]]/folder system.
"""
import json

from django.contrib.auth.hashers import make_password
from django.test import TestCase

from config.api import issue_token
from domain.accounts.models import User, CoachProfile
from domain.nutrition.models import NutritionPlan, NutritionFolder


class NutritionTemplateFolderTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(
            email='coach@example.com', password_hash=make_password('x'),
            role='COACH', is_verified=True)
        self.coach = CoachProfile.objects.create(
            user=self.user, first_name='Marco', last_name='Rossi',
            platform_subscription_status='ACTIVE', professional_type='COACH')
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {issue_token(self.user)}'}

    def _save(self, payload, plan_id=None):
        path = f'/nutrizione/piani/{plan_id}/modifica/' if plan_id else '/nutrizione/piani/crea/'
        return self.client.post(path, json.dumps(payload),
                                content_type='application/json', **self.auth)

    def test_new_plan_saved_as_template_gets_default_folder(self):
        res = self._save({'title': 'Piano tipo', 'plan_kind': 'DAILY', 'meals': [], 'is_template': True})
        self.assertEqual(res.status_code, 200)
        plan = NutritionPlan.objects.get(id=res.json()['plan_id'])
        self.assertTrue(plan.is_template)
        self.assertEqual(plan.folder.title, 'Template')

    def test_existing_plan_becoming_template_moves_into_default_folder(self):
        other = NutritionFolder.objects.create(coach=self.coach, title='Definizione')
        res = self._save({'title': 'Piano X', 'plan_kind': 'DAILY', 'meals': [], 'folder_id': other.id})
        plan_id = res.json()['plan_id']
        self.assertEqual(NutritionPlan.objects.get(id=plan_id).folder_id, other.id)

        res2 = self._save({'title': 'Piano X', 'plan_kind': 'DAILY', 'meals': [],
                           'folder_id': other.id, 'is_template': True}, plan_id=plan_id)
        self.assertEqual(res2.status_code, 200)
        plan = NutritionPlan.objects.get(id=plan_id)
        self.assertTrue(plan.is_template)
        self.assertEqual(plan.folder.title, 'Template')

    def test_already_template_respects_explicit_folder_move(self):
        # Once a plan is already a template, a later explicit folder pick
        # (reorganizing templates) must not be forced back to "Template".
        res = self._save({'title': 'Piano Y', 'plan_kind': 'DAILY', 'meals': [], 'is_template': True})
        plan_id = res.json()['plan_id']
        custom = NutritionFolder.objects.create(coach=self.coach, title='Upper/Lower templates')

        res2 = self._save({'title': 'Piano Y', 'plan_kind': 'DAILY', 'meals': [],
                           'is_template': True, 'folder_id': custom.id}, plan_id=plan_id)
        self.assertEqual(res2.status_code, 200)
        plan = NutritionPlan.objects.get(id=plan_id)
        self.assertEqual(plan.folder_id, custom.id)

    def test_draft_save_leaves_folder_untouched(self):
        res = self._save({'title': 'Piano bozza', 'plan_kind': 'DAILY', 'meals': []})
        plan_id = res.json()['plan_id']
        plan = NutritionPlan.objects.get(id=plan_id)
        self.assertFalse(plan.is_template)
        self.assertIsNone(plan.folder)
