"""Test del recap CHIRON: motore insight, forecast, guardia narrativa, e
aggregazioni body-comp. Copre la logica nuova (regole, regressione lineare,
guardia anti-allucinazione, soglie di affidabilità) — non ri-testa i KPI
training già esistenti in config/views_session.py, solo wrappati qui.
"""

import json
from datetime import date, timedelta
from unittest.mock import patch

from django.test import TestCase, Client as DjangoTestClient
from django.urls import reverse

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.billing.models import PlatformPurchase
from domain.coaching.models import CoachingRelationship
from domain.checks.models import QuestionnaireTemplate, QuestionnaireResponse

from domain.chiron.recap import insights as insights_engine
from domain.chiron.recap import forecast as forecast_engine
from domain.chiron.recap import narrative as narrative_engine
from domain.chiron.recap import aggregates_body
from domain.chiron.recap.schemas import RecapInsight, Evidence


# ---------------------------------------------------------------------------
# Forecast (regressione lineare sul peso)
# ---------------------------------------------------------------------------

class ForecastTests(TestCase):
    def test_too_few_points_unavailable(self):
        today = date(2026, 7, 20)
        series = [(today - timedelta(days=10), 80.0), (today - timedelta(days=5), 79.5)]
        result = forecast_engine.forecast_weight(series, today=today)
        self.assertFalse(result.available)

    def test_clear_downward_trend_high_confidence_down(self):
        today = date(2026, 7, 20)
        series = [(today - timedelta(days=(5 - i) * 7), 80.0 - i * 0.5) for i in range(6)]
        result = forecast_engine.forecast_weight(series, today=today)
        self.assertTrue(result.available)
        self.assertEqual(result.direction, 'down')
        self.assertEqual(result.confidence, 'high')
        self.assertLess(result.projected_2w, series[-1][1])

    def test_flat_noise_is_stable_within_dead_band(self):
        today = date(2026, 7, 20)
        series = [(today - timedelta(days=(3 - i) * 7), 80.0) for i in range(4)]
        series[1] = (series[1][0], 80.1)
        series[2] = (series[2][0], 79.9)
        result = forecast_engine.forecast_weight(series, today=today)
        self.assertTrue(result.available)
        self.assertEqual(result.direction, 'stable')

    def test_caveat_always_present(self):
        result = forecast_engine.forecast_weight([], today=date(2026, 7, 20))
        self.assertTrue(result.caveat)


class ExtendedForecastTests(TestCase):
    """Forecast V2: stessa meccanica del peso, soglie più severe perché il
    dato è più sparso/rumoroso (circonferenze, aderenza nutrizionale)."""

    def test_circumference_needs_one_more_point_than_weight(self):
        today = date(2026, 7, 20)
        # 3 punti: basterebbero per il peso (MIN_POINTS=3) ma non per la vita (4).
        series = [(today - timedelta(days=(2 - i) * 10), 90.0 - i) for i in range(3)]
        result = forecast_engine.forecast_circumference(series, 'waist', today=today)
        self.assertFalse(result.available)

    def test_circumference_clear_trend_available_with_4_points(self):
        today = date(2026, 7, 20)
        series = [(today - timedelta(days=(3 - i) * 10), 90.0 - i * 1.2) for i in range(4)]
        result = forecast_engine.forecast_circumference(series, 'waist', today=today)
        self.assertTrue(result.available)
        self.assertEqual(result.direction, 'down')
        self.assertEqual(result.metric, 'circumference_waist')

    def test_nutrition_adherence_needs_4_weekly_points(self):
        today = date(2026, 7, 20)
        series = [(today - timedelta(weeks=(2 - i)), 80.0) for i in range(3)]
        result = forecast_engine.forecast_nutrition_adherence(series, today=today)
        self.assertFalse(result.available)

    def test_nutrition_adherence_small_change_is_stable(self):
        today = date(2026, 7, 20)
        # Variazione settimana-su-settimana piccola: sotto la dead-band di 5 punti.
        series = [(today - timedelta(weeks=(3 - i)), 80.0 + i * 0.5) for i in range(4)]
        result = forecast_engine.forecast_nutrition_adherence(series, today=today)
        self.assertTrue(result.available)
        self.assertEqual(result.direction, 'stable')


# ---------------------------------------------------------------------------
# Insight engine (regole deterministiche)
# ---------------------------------------------------------------------------

class InsightsTests(TestCase):
    def test_recomposition_signal_fires(self):
        body = {
            'weight': {'reliable': True, 'delta': 0.1, 'current_avg': 80.0, 'previous_avg': 79.9,
                       'n_current': 3, 'n_previous': 3, 'series': []},
            'circumferences': {'waist': {'reliable': True, 'delta': -1.5,
                                         'current_avg': 84.0, 'previous_avg': 85.5,
                                         'n_current': 2, 'n_previous': 2}},
            'skinfolds': {},
        }
        insights = insights_engine.generate_insights(body, {'available': False, 'reliable': False}, {})
        codes = [i.code for i in insights]
        self.assertIn('recomposition_signal', codes)

    def test_custom_thresholds_override_defaults(self):
        # Stessi dati di test_recomposition_signal_fires ma con una soglia di
        # "vita in calo" più stretta della delta reale (-1.5): non deve scattare.
        body = {
            'weight': {'reliable': True, 'delta': 0.1, 'current_avg': 80.0, 'previous_avg': 79.9,
                       'n_current': 3, 'n_previous': 3, 'series': []},
            'circumferences': {'waist': {'reliable': True, 'delta': -1.5,
                                         'current_avg': 84.0, 'previous_avg': 85.5,
                                         'n_current': 2, 'n_previous': 2}},
            'skinfolds': {},
        }
        insights = insights_engine.generate_insights(
            body, {'available': False, 'reliable': False}, {},
            thresholds={'recomposition_waist_drop_cm': -2.0},
        )
        self.assertNotIn('recomposition_signal', [i.code for i in insights])

        # Default (nessun override): torna a scattare con la stessa delta.
        insights = insights_engine.generate_insights(body, {'available': False, 'reliable': False}, {})
        self.assertIn('recomposition_signal', [i.code for i in insights])

    def test_recomposition_suppressed_when_unreliable(self):
        body = {
            'weight': {'reliable': False, 'delta': 0.1, 'current_avg': 80.0, 'previous_avg': 79.9,
                       'n_current': 1, 'n_previous': 1, 'series': []},
            'circumferences': {}, 'skinfolds': {},
        }
        insights = insights_engine.generate_insights(body, {'available': False, 'reliable': False}, {})
        self.assertNotIn('recomposition_signal', [i.code for i in insights])

    def test_nutrition_weekend_gap_fires_only_when_reliable_and_large(self):
        nutrition_reliable_gap = {
            'available': True, 'reliable': True, 'n_log_days': 10, 'window_days': 30,
            'weekday_pct': 90.0, 'weekend_pct': 50.0, 'overall_pct': 75.0,
        }
        body_empty = {'weight': {'reliable': False}, 'circumferences': {}, 'skinfolds': {}}
        insights = insights_engine.generate_insights(body_empty, nutrition_reliable_gap, {})
        self.assertIn('nutrition_adherence_weekend_drop', [i.code for i in insights])

        nutrition_small_gap = {**nutrition_reliable_gap, 'weekend_pct': 85.0}
        insights = insights_engine.generate_insights(body_empty, nutrition_small_gap, {})
        self.assertNotIn('nutrition_adherence_weekend_drop', [i.code for i in insights])

    def test_low_logging_coverage_fires_when_unreliable(self):
        nutrition = {'available': True, 'reliable': False, 'n_log_days': 2, 'window_days': 30,
                     'weekday_pct': None, 'weekend_pct': None, 'overall_pct': None}
        body_empty = {'weight': {'reliable': False}, 'circumferences': {}, 'skinfolds': {}}
        insights = insights_engine.generate_insights(body_empty, nutrition, {})
        self.assertIn('low_logging_coverage', [i.code for i in insights])

    def test_exercise_dropped_and_substituted(self):
        training = {
            'exercise_compliance': {
                'available': True, 'sessions_considered': 6,
                'dropped': [{'exercise_name': 'Affondi', 'count': 4}],
                'substituted': [{'exercise_name': 'Leg press', 'count': 3}],
            },
        }
        body_empty = {'weight': {'reliable': False}, 'circumferences': {}, 'skinfolds': {}}
        nutrition_empty = {'available': False, 'reliable': False}
        insights = insights_engine.generate_insights(body_empty, nutrition_empty, training)
        codes = [i.code for i in insights]
        self.assertIn('exercise_dropped', codes)
        self.assertIn('exercise_substituted_often', codes)

    def test_result_despite_low_adherence(self):
        body = {'weight': {'reliable': True, 'delta': -2.0, 'current_avg': 78.0, 'previous_avg': 80.0,
                           'n_current': 3, 'n_previous': 3, 'series': []},
                'circumferences': {}, 'skinfolds': {}}
        training = {'adherence': {'overall_pct': 40.0, 'series': []}}
        insights = insights_engine.generate_insights(body, {'available': False, 'reliable': False}, training)
        self.assertIn('result_despite_low_adherence', [i.code for i in insights])

    def test_overreaching_signal(self):
        training = {'rpe': {'series': [
            {'week': '2026-06-01', 'avg_rpe': 6.0},
            {'week': '2026-06-08', 'avg_rpe': 6.2},
            {'week': '2026-06-15', 'avg_rpe': 7.5},
            {'week': '2026-06-22', 'avg_rpe': 8.0},
        ]}}
        body_empty = {'weight': {'reliable': False}, 'circumferences': {}, 'skinfolds': {}}
        insights = insights_engine.generate_insights(body_empty, {'available': False, 'reliable': False}, training)
        self.assertIn('overreaching_signal', [i.code for i in insights])

    def test_overreaching_mentions_declining_sleep_as_qualifier_only(self):
        training = {
            'rpe': {'series': [
                {'week': '2026-06-01', 'avg_rpe': 6.0}, {'week': '2026-06-08', 'avg_rpe': 6.2},
                {'week': '2026-06-15', 'avg_rpe': 7.5}, {'week': '2026-06-22', 'avg_rpe': 8.0},
            ]},
            'sleep_signal': {'available': True, 'latest': 2.0, 'trend': 'declining'},
        }
        body_empty = {'weight': {'reliable': False}, 'circumferences': {}, 'skinfolds': {}}
        insights = insights_engine.generate_insights(body_empty, {'available': False, 'reliable': False}, training)
        overreaching = next(i for i in insights if i.code == 'overreaching_signal')
        self.assertIn('sonno', overreaching.observation.lower())
        # Confidence resta guidata solo da RPE — il sonno è testo, non un input numerico.
        self.assertEqual(overreaching.confidence, 'medium')

    def test_plateau_prefers_load_signal_over_volume_when_available(self):
        training = {
            'top_exercise_load': {
                'available': True, 'name': 'barbell bench squat',
                'sessions': [{'top_set': v} for v in [100, 100, 100, 80, 80, 80]],
            },
            'volume': {'weeks': [], 'series': {}},  # nessun dato volume: se scattasse, sarebbe un bug
        }
        insights = insights_engine.generate_insights(
            {'weight': {'reliable': False}, 'circumferences': {}, 'skinfolds': {}},
            {'available': False, 'reliable': False}, training,
        )
        plateau = next((i for i in insights if i.code == 'plateau_load'), None)
        self.assertIsNotNone(plateau)
        self.assertIn('squat', plateau.observation.lower())
        self.assertEqual(plateau.evidence.metric, 'top_set_load')

    def test_plateau_falls_back_to_volume_when_no_load_trend(self):
        weeks = [f'2026-0{i}-01' for i in range(1, 7)]
        series = {'Petto': [100, 100, 100, 100, 100, 100], 'Gambe': [100, 100, 100, 60, 60, 60]}
        training = {
            'top_exercise_load': {'available': False, 'name': None, 'sessions': []},
            'volume': {'weeks': weeks, 'series': series},
        }
        insights = insights_engine.generate_insights(
            {'weight': {'reliable': False}, 'circumferences': {}, 'skinfolds': {}},
            {'available': False, 'reliable': False}, training,
        )
        plateau = next((i for i in insights if i.code == 'plateau_load'), None)
        self.assertIsNotNone(plateau)
        self.assertEqual(plateau.evidence.metric, 'volume_total')

    def test_every_insight_has_non_empty_interpretation(self):
        # observation/interpretation sono SEMPRE template deterministici — mai vuoti.
        body = {'weight': {'reliable': True, 'delta': 0.1, 'current_avg': 80.0, 'previous_avg': 79.9,
                           'n_current': 3, 'n_previous': 3, 'series': []},
                'circumferences': {'waist': {'reliable': True, 'delta': -2.0, 'current_avg': 84.0,
                                             'previous_avg': 86.0, 'n_current': 2, 'n_previous': 2}},
                'skinfolds': {}}
        insights = insights_engine.generate_insights(body, {'available': False, 'reliable': False}, {})
        for insight in insights:
            self.assertTrue(insight.interpretation)
            self.assertTrue(insight.observation)


# ---------------------------------------------------------------------------
# Narrativa: guardia anti-allucinazione + fallback
# ---------------------------------------------------------------------------

class NarrativeTests(TestCase):
    def test_empty_insights_returns_template_without_llm_call(self):
        with patch.object(narrative_engine, 'build_narrative_llm') as mock_build:
            text, is_fallback = narrative_engine.generate_narrative([])
            mock_build.assert_not_called()
        self.assertFalse(is_fallback)
        self.assertTrue(text)

    def _insight(self):
        return RecapInsight(
            code='recomposition_signal', domain='cross',
            observation='Peso stabile (Δ+0.1kg), vita in calo (Δ-1.5cm).',
            interpretation='Probabile ricomposizione corporea favorevole.',
            recommendation='Mantenere la direzione attuale.',
            confidence='medium',
            evidence=Evidence(metric='weight_vs_waist', window='30d', current_value=0.1, previous_value=-1.5),
        )

    def test_llm_failure_falls_back_to_template(self):
        with patch.object(narrative_engine, 'build_narrative_llm', side_effect=RuntimeError('boom')):
            text, is_fallback = narrative_engine.generate_narrative([self._insight()])
        self.assertTrue(is_fallback)
        self.assertIn('ricomposizione', text.lower())

    def test_llm_inventing_a_number_triggers_fallback(self):
        class _FakeResponse:
            content = "L'atleta ha perso 12kg questo mese, un risultato eccezionale."

        class _FakeLLM:
            def invoke(self, messages):
                return _FakeResponse()

        with patch.object(narrative_engine, 'build_narrative_llm', return_value=_FakeLLM()):
            text, is_fallback = narrative_engine.generate_narrative([self._insight()])
        self.assertTrue(is_fallback)

    def test_llm_text_using_only_known_numbers_is_accepted(self):
        class _FakeResponse:
            content = "Il peso è rimasto stabile (0.1) mentre la vita è calata di 1.5 cm: buon segnale."

        class _FakeLLM:
            def invoke(self, messages):
                return _FakeResponse()

        with patch.object(narrative_engine, 'build_narrative_llm', return_value=_FakeLLM()):
            text, is_fallback = narrative_engine.generate_narrative([self._insight()])
        self.assertFalse(is_fallback)


# ---------------------------------------------------------------------------
# Aggregazioni body-comp: soglie di affidabilità + esclusione outlier
# ---------------------------------------------------------------------------

class BodyCompAggregateTests(TestCase):
    def setUp(self):
        cu = User.objects.create(email='coach_bc@demo.com', password_hash='x', role='COACH')
        self.coach = CoachProfile.objects.create(user=cu, first_name='Coach', last_name='Demo')
        clu = User.objects.create(email='client_bc@demo.com', password_hash='x', role='CLIENT')
        self.client_p = ClientProfile.objects.create(user=clu, first_name='Cli', last_name='Ent')
        self.template = QuestionnaireTemplate.objects.create(
            coach=self.coach, title='Check', questionnaire_type='quick_measurement',
        )

    def _response(self, days_ago, weight_kg, waist=None):
        from django.utils import timezone
        submitted = timezone.now() - timedelta(days=days_ago)
        return QuestionnaireResponse.objects.create(
            questionnaire_template=self.template, client=self.client_p, coach=self.coach,
            submitted_at=submitted, status='REVIEWED', weight_kg=weight_kg,
            body_circumferences={'waist': waist} if waist is not None else {},
        )

    def test_insufficient_points_marked_unreliable(self):
        self._response(5, 80.0)
        result = aggregates_body.compute_body_comp(self.client_p)
        self.assertFalse(result['weight']['reliable'])

    def test_enough_points_marked_reliable_with_delta(self):
        self._response(50, 82.0)
        self._response(40, 81.5)
        self._response(10, 80.0)
        self._response(5, 79.5)
        result = aggregates_body.compute_body_comp(self.client_p)
        self.assertTrue(result['weight']['reliable'])
        self.assertIsNotNone(result['weight']['delta'])

    def test_outlier_weight_excluded(self):
        # 999kg è fuori dal range plausibile (20-400) e non deve inquinare la media.
        self._response(50, 82.0)
        self._response(40, 999.0)
        self._response(10, 80.0)
        result = aggregates_body.compute_body_comp(self.client_p)
        for _d, v in result['weight']['series']:
            self.assertLess(v, 400)

    def test_waist_key_independent_reliability_from_weight(self):
        # Molte pesate rapide (peso affidabile) ma un solo dato vita (non affidabile).
        for days_ago in (60, 45, 30, 15, 5):
            self._response(days_ago, 80.0)
        self._response(5, 80.0, waist='85.0')
        result = aggregates_body.compute_body_comp(self.client_p)
        self.assertTrue(result['weight']['reliable'])
        self.assertFalse(result['circumferences']['waist']['reliable'])


# ---------------------------------------------------------------------------
# Training aggregates V2: trend di carico sull'esercizio principale + segnale
# sonno auto-riportato (usati dalle regole plateau/overreaching potenziate).
# ---------------------------------------------------------------------------

class TrainingAggregateTests(TestCase):
    def setUp(self):
        from domain.workouts.models import (
            Exercise, WorkoutPlan, WorkoutDay, WorkoutExercise, WorkoutAssignment,
        )
        cu = User.objects.create(email='coach_ta@demo.com', password_hash='x', role='COACH')
        self.coach = CoachProfile.objects.create(user=cu, first_name='Coach', last_name='Demo')
        clu = User.objects.create(email='client_ta@demo.com', password_hash='x', role='CLIENT')
        self.client_p = ClientProfile.objects.create(user=clu, first_name='Cli', last_name='Ent')
        self.exercise = Exercise.objects.create(name='Test Squat', slug='test-squat-ta')
        plan = WorkoutPlan.objects.create(coach=self.coach, title='Piano', status='ACTIVE', frequency_per_week=3)
        day = WorkoutDay.objects.create(workout_plan=plan, day_order=1, day_name='Full body')
        self.we = WorkoutExercise.objects.create(
            workout_day=day, exercise=self.exercise, order_index=1, set_count=1, rep_count=5,
        )
        self.assignment = WorkoutAssignment.objects.create(
            workout_plan=plan, client=self.client_p, coach=self.coach, status='ACTIVE',
            start_date=date.today() - timedelta(days=60),
        )

    def _session_with_load(self, days_ago, load):
        from django.utils import timezone
        from domain.workouts.models import WorkoutSession, WorkoutSetLog
        session = WorkoutSession.objects.create(
            assignment=self.assignment, workout_day=self.we.workout_day, client=self.client_p,
            started_at=timezone.now() - timedelta(days=days_ago), completed=True,
        )
        WorkoutSetLog.objects.create(
            session=session, workout_exercise=self.we, set_number=1,
            reps_done=5, load_used=load, rpe=7, completed=True,
        )

    def test_top_exercise_load_trend_unavailable_below_min_sessions(self):
        from domain.chiron.recap.aggregates_training import compute_top_exercise_load_trend
        for days_ago in (20, 15, 10):
            self._session_with_load(days_ago, 100)
        result = compute_top_exercise_load_trend(self.client_p, min_sessions=6)
        self.assertFalse(result['available'])

    def test_top_exercise_load_trend_available_with_enough_sessions(self):
        from domain.chiron.recap.aggregates_training import compute_top_exercise_load_trend
        for i, days_ago in enumerate([50, 40, 30, 20, 10, 5]):
            self._session_with_load(days_ago, 100 - i)
        result = compute_top_exercise_load_trend(self.client_p, min_sessions=6)
        self.assertTrue(result['available'])
        self.assertEqual(result['name'], 'Test Squat')
        self.assertEqual(len(result['sessions']), 6)

    def test_sleep_signal_unavailable_when_no_check_has_it(self):
        from domain.chiron.recap.aggregates_training import compute_recent_sleep_signal
        result = compute_recent_sleep_signal(self.client_p)
        self.assertFalse(result['available'])

    def test_sleep_signal_declining_trend(self):
        from django.utils import timezone
        from domain.chiron.recap.aggregates_training import compute_recent_sleep_signal
        tpl = QuestionnaireTemplate.objects.create(
            coach=self.coach, title='Check', questionnaire_type='rapido_atleta',
        )
        for days_ago, sonno in [(15, 5), (8, 3), (1, 2)]:
            QuestionnaireResponse.objects.create(
                questionnaire_template=tpl, client=self.client_p, coach=self.coach,
                submitted_at=timezone.now() - timedelta(days=days_ago), status='REVIEWED',
                answers_json={'benessere_sonno': sonno},
            )
        result = compute_recent_sleep_signal(self.client_p)
        self.assertTrue(result['available'])
        self.assertEqual(result['trend'], 'declining')
        self.assertEqual(result['latest'], 2.0)


# ---------------------------------------------------------------------------
# Storico recap (V2): append-only invece di upsert, confronto col precedente.
# ---------------------------------------------------------------------------

class RecapHistoryTests(TestCase):
    def setUp(self):
        from django.core.cache import cache
        from domain.chiron.recap.builder import build_recap
        self.build_recap = build_recap
        # Il cache backend non è azzerato dal rollback di transazione di
        # TestCase (a differenza del DB) — senza questo, un coach_id/client_id
        # riusato da un test precedente nella stessa run può far leggere
        # aggregati stale sotto la stessa cache key (cachekeys.athlete_recap).
        cache.clear()

        cu = User.objects.create(email='coach_hist@demo.com', password_hash='x', role='COACH')
        self.coach = CoachProfile.objects.create(user=cu, first_name='Coach', last_name='Demo',
                                                  professional_type='COACH')
        purchase = PlatformPurchase.objects.create(
            email='coach_hist@demo.com', code='ATHLYNK-TEST-HIST', has_chiron=True,
            status=PlatformPurchase.STATUS_ACTIVE, stripe_session_id='sess_test_hist',
        )
        self.coach.platform_purchase = purchase
        self.coach.save(update_fields=['platform_purchase'])

        clu = User.objects.create(email='client_hist@demo.com', password_hash='x', role='CLIENT')
        self.client_p = ClientProfile.objects.create(user=clu, first_name='Storico', last_name='Test')
        CoachingRelationship.objects.create(
            coach=self.coach, client=self.client_p, status='ACTIVE',
            start_date=date.today() - timedelta(days=30), relationship_type='FULL',
        )
        self.template = QuestionnaireTemplate.objects.create(
            coach=self.coach, title='Check', questionnaire_type='quick_measurement',
        )

    def _add_weight_check(self, days_ago, weight_kg):
        from django.utils import timezone
        QuestionnaireResponse.objects.create(
            questionnaire_template=self.template, client=self.client_p, coach=self.coach,
            submitted_at=timezone.now() - timedelta(days=days_ago), status='REVIEWED',
            weight_kg=weight_kg,
        )

    def test_first_recap_has_no_comparison(self):
        from domain.chiron.models import AthleteRecap
        payload = self.build_recap(self.coach, self.client_p)
        self.assertFalse(payload.comparison.available)
        self.assertEqual(AthleteRecap.objects.filter(coach=self.coach, client=self.client_p).count(), 1)

    def test_unchanged_data_does_not_grow_history(self):
        from domain.chiron.models import AthleteRecap
        self.build_recap(self.coach, self.client_p)
        self.build_recap(self.coach, self.client_p)  # stessi dati, non forzato
        self.assertEqual(AthleteRecap.objects.filter(coach=self.coach, client=self.client_p).count(), 1)

    def test_changed_data_appends_and_reports_comparison(self):
        from domain.chiron.models import AthleteRecap
        self._add_weight_check(20, 80.0)
        first = self.build_recap(self.coach, self.client_p)
        self.assertFalse(first.comparison.available)

        self._add_weight_check(1, 78.0)
        second = self.build_recap(self.coach, self.client_p, force_refresh=True)
        self.assertTrue(second.comparison.available)
        self.assertIsNotNone(second.comparison.weight_delta_since_last_recap)
        self.assertEqual(AthleteRecap.objects.filter(coach=self.coach, client=self.client_p).count(), 2)

    def test_force_refresh_appends_even_without_data_change(self):
        from domain.chiron.models import AthleteRecap
        self.build_recap(self.coach, self.client_p)
        self.build_recap(self.coach, self.client_p, force_refresh=True)
        self.assertEqual(AthleteRecap.objects.filter(coach=self.coach, client=self.client_p).count(), 2)

    def test_history_endpoint_lists_newest_first(self):
        http = DjangoTestClient()
        session = http.session
        session['user_id'] = self.coach.user_id
        session.save()

        self.build_recap(self.coach, self.client_p)
        self.build_recap(self.coach, self.client_p, force_refresh=True)

        url = reverse('api_chiron_recap_history', args=[self.client_p.id])
        response = http.get(url)
        self.assertEqual(response.status_code, 200)
        history = response.json()['history']
        self.assertEqual(len(history), 2)
        self.assertGreater(history[0]['generated_at'], history[1]['generated_at'])


# ---------------------------------------------------------------------------
# Smoke test end-to-end: atleta con storico minimo, endpoint deve rendere
# senza errori (nessuna chiamata LLM reale: insights=[] con dati vuoti).
# ---------------------------------------------------------------------------

class RecapEndpointSmokeTest(TestCase):
    def setUp(self):
        cu = User.objects.create(email='coach_e2e@demo.com', password_hash='x', role='COACH')
        self.coach = CoachProfile.objects.create(user=cu, first_name='Coach', last_name='Demo',
                                                  professional_type='COACH')
        purchase = PlatformPurchase.objects.create(
            email='coach_e2e@demo.com', code='ATHLYNK-TEST-0001', has_chiron=True,
            status=PlatformPurchase.STATUS_ACTIVE, stripe_session_id='sess_test_recap',
        )
        self.coach.platform_purchase = purchase
        self.coach.save(update_fields=['platform_purchase'])

        clu = User.objects.create(email='client_e2e@demo.com', password_hash='x', role='CLIENT')
        self.client_p = ClientProfile.objects.create(user=clu, first_name='Athlete', last_name='Zero')
        CoachingRelationship.objects.create(
            coach=self.coach, client=self.client_p, status='ACTIVE',
            start_date=date.today() - timedelta(days=30), relationship_type='FULL',
        )
        self.http = DjangoTestClient()
        session = self.http.session
        session['user_id'] = cu.id
        session.save()

    def test_recap_renders_with_no_history(self):
        url = reverse('api_chiron_recap', args=[self.client_p.id])
        response = self.http.get(url)
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload['insights'], [])
        self.assertFalse(payload['forecast']['available'])
        self.assertTrue(payload['sections_available']['training'])
        self.assertTrue(payload['sections_available']['nutrition'])

    def test_recap_page_renders(self):
        url = reverse('coach_client_recap', args=[self.client_p.id])
        response = self.http.get(url)
        self.assertEqual(response.status_code, 200)
        self.assertIn(b'coachRecap', response.content)

    def test_recap_forbidden_for_unrelated_coach(self):
        other_cu = User.objects.create(email='other_coach@demo.com', password_hash='x', role='COACH')
        other_coach = CoachProfile.objects.create(user=other_cu, first_name='Other', last_name='Coach')
        purchase = PlatformPurchase.objects.create(
            email='other_coach@demo.com', code='ATHLYNK-TEST-0002', has_chiron=True,
            status=PlatformPurchase.STATUS_ACTIVE, stripe_session_id='sess_test_recap_2',
        )
        other_coach.platform_purchase = purchase
        other_coach.save(update_fields=['platform_purchase'])

        other_http = DjangoTestClient()
        session = other_http.session
        session['user_id'] = other_cu.id
        session.save()

        url = reverse('api_chiron_recap', args=[self.client_p.id])
        response = other_http.get(url)
        self.assertEqual(response.status_code, 403)

    def test_insight_action_unknown_code_rejected(self):
        url = reverse('api_chiron_recap_insight_action', args=[self.client_p.id])
        response = self.http.post(url, data='{"insight_code": "not_a_real_code"}',
                                   content_type='application/json')
        self.assertEqual(response.status_code, 400)

    def test_insight_action_builds_send_message_proposal(self):
        url = reverse('api_chiron_recap_insight_action', args=[self.client_p.id])
        response = self.http.post(url, data='{"insight_code": "overreaching_signal"}',
                                   content_type='application/json')
        self.assertEqual(response.status_code, 200)
        proposal = response.json()['proposal']
        self.assertEqual(proposal['action_type'], 'send_message')
        self.assertEqual(proposal['client_id'], self.client_p.id)
        self.assertIn('RPE', proposal['payload']['message'])

    def test_insight_action_forbidden_for_unrelated_coach(self):
        other_cu = User.objects.create(email='other_coach2@demo.com', password_hash='x', role='COACH')
        other_coach = CoachProfile.objects.create(user=other_cu, first_name='Other', last_name='Coach')
        purchase = PlatformPurchase.objects.create(
            email='other_coach2@demo.com', code='ATHLYNK-TEST-0003', has_chiron=True,
            status=PlatformPurchase.STATUS_ACTIVE, stripe_session_id='sess_test_recap_3',
        )
        other_coach.platform_purchase = purchase
        other_coach.save(update_fields=['platform_purchase'])
        other_http = DjangoTestClient()
        session = other_http.session
        session['user_id'] = other_cu.id
        session.save()

        url = reverse('api_chiron_recap_insight_action', args=[self.client_p.id])
        response = other_http.post(url, data='{"insight_code": "overreaching_signal"}',
                                    content_type='application/json')
        self.assertEqual(response.status_code, 403)

    def test_insight_feedback_requires_useful_boolean(self):
        url = reverse('api_chiron_recap_insight_feedback', args=[self.client_p.id])
        response = self.http.post(url, data='{"insight_code": "plateau_load"}',
                                   content_type='application/json')
        self.assertEqual(response.status_code, 400)

    def test_insight_feedback_saved_and_reclick_updates_not_duplicates(self):
        from domain.chiron.models import AthleteRecapFeedback
        url = reverse('api_chiron_recap_insight_feedback', args=[self.client_p.id])

        response = self.http.post(url, data='{"insight_code": "plateau_load", "useful": true}',
                                   content_type='application/json')
        self.assertEqual(response.status_code, 200)
        response = self.http.post(url, data='{"insight_code": "plateau_load", "useful": false}',
                                   content_type='application/json')
        self.assertEqual(response.status_code, 200)

        rows = AthleteRecapFeedback.objects.filter(coach=self.coach, client=self.client_p, insight_code='plateau_load')
        self.assertEqual(rows.count(), 1)
        self.assertFalse(rows.first().useful)

    def test_recap_settings_get_returns_defaults_when_never_set(self):
        from domain.chiron.recap.insights import DEFAULT_THRESHOLDS
        url = reverse('api_chiron_recap_settings')
        response = self.http.get(url)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['thresholds'], DEFAULT_THRESHOLDS)

    def test_recap_settings_post_persists_and_ignores_unknown_keys(self):
        from domain.chiron.models import CoachRecapSettings
        url = reverse('api_chiron_recap_settings')
        response = self.http.post(url, data=json.dumps({
            'thresholds': {'overreaching_rpe_delta': 1.2, 'not_a_real_key': 999},
        }), content_type='application/json')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['thresholds']['overreaching_rpe_delta'], 1.2)
        self.assertNotIn('not_a_real_key', response.json()['thresholds'])

        row = CoachRecapSettings.objects.get(coach=self.coach)
        self.assertEqual(row.thresholds, {'overreaching_rpe_delta': 1.2})

    def test_recap_settings_requires_login(self):
        url = reverse('api_chiron_recap_settings')
        response = DjangoTestClient().get(url)
        self.assertEqual(response.status_code, 401)
