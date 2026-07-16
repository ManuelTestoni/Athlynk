"""Smoke test: coach client-detail page renders after the 4-card grid was
replaced with the week-strip + domain-selector panel (templates/pages/clienti/detail.html)."""
from datetime import date

from django.contrib.auth.hashers import make_password
from django.test import TestCase, override_settings

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.coaching.models import CoachingRelationship

LOCMEM = {'default': {'BACKEND': 'django.core.cache.backends.locmem.LocMemCache'}}


@override_settings(CACHES=LOCMEM)
class ClientDetailPageTests(TestCase):
    def setUp(self):
        cu = User.objects.create(email='c@e.com', password_hash=make_password('x'),
                                 role='COACH', is_verified=True)
        self.coach = CoachProfile.objects.create(user=cu, first_name='C', last_name='O',
                                                 professional_type='COACH')
        au = User.objects.create(email='a@e.com', password_hash=make_password('x'),
                                 role='CLIENT', is_verified=True)
        self.athlete = ClientProfile.objects.create(user=au, first_name='A', last_name='T')
        CoachingRelationship.objects.create(coach=self.coach, client=self.athlete,
                                            status='ACTIVE', start_date=date.today())
        session = self.client.session
        session['user_id'] = cu.id
        session.save()

    def test_renders_with_no_data(self):
        r = self.client.get(f'/clienti/{self.athlete.id}/')
        self.assertEqual(r.status_code, 200)
        self.assertContains(r, 'clientDetailPanel')
        self.assertContains(r, 'Nessun piano attivo')
