"""Customizable dashboard layout: registry validation, role defaults,
Bearer + session endpoints, cache invalidation, pinned-athletes scoping."""
import json
from datetime import date

from django.contrib.auth.hashers import make_password
from django.core.cache import cache
from django.test import TestCase

from config import dashboard_widgets
from config.api import issue_token
from config.services import cachekeys
from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.coaching.models import CoachingRelationship


def _mk_coach(email='coach@example.com'):
    user = User.objects.create(
        email=email, password_hash=make_password('x'),
        role='COACH', is_verified=True)
    coach = CoachProfile.objects.create(
        user=user, first_name='Marco', last_name='Rossi',
        platform_subscription_status='ACTIVE', professional_type='COACH')
    return user, coach


def _mk_client(coach, email='atleta@example.com', status='ACTIVE'):
    user = User.objects.create(
        email=email, password_hash=make_password('x'),
        role='CLIENT', is_verified=True)
    client = ClientProfile.objects.create(user=user, first_name='Luca', last_name='Bianchi')
    CoachingRelationship.objects.create(
        coach=coach, client=client, status=status,
        start_date=date.today(), relationship_type='FULL')
    return user, client


class LayoutCoreTests(TestCase):
    def setUp(self):
        cache.clear()
        self.coach_user, self.coach = _mk_coach()
        self.client_user, self.client_profile = _mk_client(self.coach)

    def test_default_layout_per_role(self):
        coach_layout = dashboard_widgets.get_layout(self.coach_user)
        types = [w['type'] for w in coach_layout['widgets']]
        self.assertEqual(types, ['recent_clients', 'subscription_plans'])

        cache.clear()
        client_layout = dashboard_widgets.get_layout(self.client_user)
        types = [w['type'] for w in client_layout['widgets']]
        self.assertEqual(types, ['weight_trend', 'training_loads',
                                 'weekly_volume', 'nav_shortcuts'])

    def test_save_round_trip_sorted(self):
        saved = dashboard_widgets.validate_and_save_layout(self.coach_user, {
            'version': 1,
            'widgets': [
                {'id': 'b', 'type': 'agenda_today', 'x': 0, 'y': 4, 'size': 'M', 'config': {}},
                {'id': 'a', 'type': 'recent_clients', 'x': 0, 'y': 0, 'size': 'M', 'config': {}},
            ],
        })
        self.assertEqual([w['type'] for w in saved['widgets']],
                         ['recent_clients', 'agenda_today'])
        self.coach_user.refresh_from_db()
        self.assertEqual(self.coach_user.dashboard_layout, saved)

    def test_wrong_role_widget_rejected(self):
        with self.assertRaises(dashboard_widgets.LayoutValidationError):
            dashboard_widgets.validate_and_save_layout(self.coach_user, {
                'version': 1,
                'widgets': [{'id': 'x', 'type': 'weight_trend',
                             'x': 0, 'y': 0, 'size': 'M', 'config': {}}],
            })

    def test_unknown_type_rejected(self):
        with self.assertRaises(dashboard_widgets.LayoutValidationError):
            dashboard_widgets.validate_and_save_layout(self.coach_user, {
                'version': 1,
                'widgets': [{'id': 'x', 'type': 'nope',
                             'x': 0, 'y': 0, 'size': 'M', 'config': {}}],
            })

    def test_bad_version_409(self):
        with self.assertRaises(dashboard_widgets.LayoutValidationError) as ctx:
            dashboard_widgets.validate_and_save_layout(self.coach_user,
                                                       {'version': 99, 'widgets': []})
        self.assertEqual(ctx.exception.status, 409)

    def test_size_clamped_to_default(self):
        saved = dashboard_widgets.validate_and_save_layout(self.coach_user, {
            'version': 1,
            'widgets': [{'id': 'x', 'type': 'recent_clients',
                         'x': 0, 'y': 0, 'size': 'XXL', 'config': {}}],
        })
        self.assertEqual(saved['widgets'][0]['size'], 'M')

    def test_duplicate_type_dropped(self):
        saved = dashboard_widgets.validate_and_save_layout(self.coach_user, {
            'version': 1,
            'widgets': [
                {'id': 'a', 'type': 'agenda_today', 'x': 0, 'y': 0, 'size': 'M', 'config': {}},
                {'id': 'b', 'type': 'agenda_today', 'x': 6, 'y': 0, 'size': 'M', 'config': {}},
            ],
        })
        self.assertEqual(len(saved['widgets']), 1)

    def test_pinned_config_strips_unlinked_client(self):
        other_coach_user, other_coach = _mk_coach('altro@example.com')
        _, foreign_client = _mk_client(other_coach, 'estraneo@example.com')
        saved = dashboard_widgets.validate_and_save_layout(self.coach_user, {
            'version': 1,
            'widgets': [{'id': 'p', 'type': 'pinned_athletes', 'x': 0, 'y': 0,
                         'size': 'M',
                         'config': {'client_ids': [self.client_profile.id,
                                                   foreign_client.id]}}],
        })
        self.assertEqual(saved['widgets'][0]['config']['client_ids'],
                         [self.client_profile.id])

    def test_reset_returns_default(self):
        dashboard_widgets.validate_and_save_layout(self.coach_user, {
            'version': 1,
            'widgets': [{'id': 'x', 'type': 'agenda_today',
                         'x': 0, 'y': 0, 'size': 'M', 'config': {}}],
        })
        layout = dashboard_widgets.reset_layout(self.coach_user)
        self.assertEqual([w['type'] for w in layout['widgets']],
                         ['recent_clients', 'subscription_plans'])
        self.coach_user.refresh_from_db()
        self.assertEqual(self.coach_user.dashboard_layout, {})

    def test_cache_invalidated_on_write(self):
        first = dashboard_widgets.get_layout(self.coach_user)
        self.assertIsNotNone(cache.get(cachekeys.dashboard_layout(self.coach_user.id)))
        dashboard_widgets.validate_and_save_layout(self.coach_user, {
            'version': 1,
            'widgets': [{'id': 'x', 'type': 'agenda_today',
                         'x': 0, 'y': 0, 'size': 'M', 'config': {}}],
        })
        self.assertIsNone(cache.get(cachekeys.dashboard_layout(self.coach_user.id)))
        second = dashboard_widgets.get_layout(self.coach_user)
        self.assertNotEqual(first, second)

    def test_catalog_role_filtered(self):
        coach_types = {c['type'] for c in dashboard_widgets.catalog_for(self.coach_user)}
        self.assertIn('recent_clients', coach_types)
        self.assertNotIn('weight_trend', coach_types)
        client_types = {c['type'] for c in dashboard_widgets.catalog_for(self.client_user)}
        self.assertIn('weight_trend', client_types)
        self.assertNotIn('recent_clients', client_types)


class MobileEndpointTests(TestCase):
    def setUp(self):
        cache.clear()
        self.coach_user, self.coach = _mk_coach()
        self.client_user, self.client_profile = _mk_client(self.coach)
        self.coach_auth = {'HTTP_AUTHORIZATION': f'Bearer {issue_token(self.coach_user)}'}
        self.client_auth = {'HTTP_AUTHORIZATION': f'Bearer {issue_token(self.client_user)}'}

    def test_requires_token(self):
        res = self.client.get('/api/v1/dashboard/layout')
        self.assertEqual(res.status_code, 401)

    def test_get_returns_layout_and_catalog(self):
        res = self.client.get('/api/v1/dashboard/layout', **self.coach_auth)
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertIn('layout', body)
        self.assertIn('catalog', body)
        self.assertEqual(res['Cache-Control'], 'no-store')

    def test_put_and_delete_round_trip(self):
        res = self.client.put('/api/v1/dashboard/layout', json.dumps({
            'version': 1,
            'widgets': [{'id': 'x', 'type': 'agenda_today',
                         'x': 0, 'y': 0, 'size': 'M', 'config': {}}],
        }), content_type='application/json', **self.coach_auth)
        self.assertEqual(res.status_code, 200)
        self.assertEqual([w['type'] for w in res.json()['layout']['widgets']],
                         ['agenda_today'])

        res = self.client.delete('/api/v1/dashboard/layout', **self.coach_auth)
        self.assertEqual(res.status_code, 200)
        self.assertEqual([w['type'] for w in res.json()['layout']['widgets']],
                         ['recent_clients', 'subscription_plans'])

    def test_put_wrong_role_widget_400(self):
        res = self.client.put('/api/v1/dashboard/layout', json.dumps({
            'version': 1,
            'widgets': [{'id': 'x', 'type': 'recent_clients',
                         'x': 0, 'y': 0, 'size': 'M', 'config': {}}],
        }), content_type='application/json', **self.client_auth)
        self.assertEqual(res.status_code, 400)

    def test_client_layout_works_with_active_coach(self):
        res = self.client.get('/api/v1/dashboard/layout', **self.client_auth)
        self.assertEqual(res.status_code, 200)
        types = [w['type'] for w in res.json()['layout']['widgets']]
        self.assertIn('weight_trend', types)

    def test_pinned_athletes_scoped(self):
        other_coach_user, other_coach = _mk_coach('altro@example.com')
        _, foreign_client = _mk_client(other_coach, 'estraneo@example.com')
        res = self.client.get(
            f'/api/v1/coach/pinned-athletes?ids={self.client_profile.id},{foreign_client.id}',
            **self.coach_auth)
        self.assertEqual(res.status_code, 200)
        ids = [a['id'] for a in res.json()['athletes']]
        self.assertEqual(ids, [self.client_profile.id])


class WebEndpointTests(TestCase):
    def setUp(self):
        cache.clear()
        self.coach_user, self.coach = _mk_coach()
        session = self.client.session
        session['user_id'] = self.coach_user.id
        session['user_role'] = 'COACH'
        session.save()

    def test_get_layout_session(self):
        res = self.client.get('/dashboard/layout')
        self.assertEqual(res.status_code, 200)
        self.assertIn('layout', res.json())

    def test_put_layout_session(self):
        res = self.client.put('/dashboard/layout', json.dumps({
            'version': 1,
            'widgets': [{'id': 'x', 'type': 'agenda_today',
                         'x': 0, 'y': 0, 'size': 'M', 'config': {}}],
        }), content_type='application/json')
        self.assertEqual(res.status_code, 200)
        self.coach_user.refresh_from_db()
        self.assertEqual(self.coach_user.dashboard_layout['widgets'][0]['type'],
                         'agenda_today')

    def test_unauthenticated_401(self):
        fresh = self.client_class()
        res = fresh.get('/dashboard/layout')
        self.assertEqual(res.status_code, 401)
