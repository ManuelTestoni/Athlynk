"""Test per domain.nutrition.adherence: aderenza nutrizionale, split
feriale/weekend, soglia di affidabilità (nuova logica, nessun precedente)."""

from datetime import date, timedelta

from django.test import TestCase

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.nutrition.models import NutritionPlan, NutritionAssignment, Food, ClientMacroLogEntry
from domain.nutrition import adherence


class NutritionAdherenceTests(TestCase):
    def setUp(self):
        cu = User.objects.create(email='coach_nut@demo.com', password_hash='x', role='COACH')
        self.coach = CoachProfile.objects.create(user=cu, first_name='Coach', last_name='Demo')
        clu = User.objects.create(email='client_nut@demo.com', password_hash='x', role='CLIENT')
        self.client_p = ClientProfile.objects.create(user=clu, first_name='Cli', last_name='Ent')
        self.food = Food.objects.create(nome_alimento='Pollo', energia_kcal=100)  # 100 kcal / 100g

    def _macro_assignment(self, daily_kcal=2000):
        plan = NutritionPlan.objects.create(
            coach=self.coach, title='Piano macro', plan_kind='DAILY', plan_mode='MACRO',
            daily_kcal=daily_kcal, status='PUBLISHED',
        )
        return NutritionAssignment.objects.create(
            nutrition_plan=plan, client=self.client_p, coach=self.coach, status='ACTIVE',
        )

    def test_no_macro_assignment_returns_unavailable(self):
        result = adherence.compute_adherence(self.client_p)
        self.assertFalse(result['available'])

    def test_below_min_reliable_days_marked_unreliable(self):
        assignment = self._macro_assignment(daily_kcal=2000)
        ClientMacroLogEntry.objects.create(
            assignment=assignment, log_date=date.today() - timedelta(days=1),
            food=self.food, quantity_g=2000,  # 2000 kcal = 100% target
        )
        result = adherence.compute_adherence(self.client_p)
        self.assertTrue(result['available'])
        self.assertEqual(result['n_log_days'], 1)
        self.assertFalse(result['reliable'])

    def test_weekday_weekend_split(self):
        assignment = self._macro_assignment(daily_kcal=2000)
        today = date.today()
        # Costruisce 6 giorni loggati: 4 feriali al 100% target, 2 weekend al 50%.
        logged = 0
        d = today - timedelta(days=1)
        weekday_days, weekend_days = 0, 0
        while logged < 6:
            if d.weekday() < 5 and weekday_days < 4:
                qty = 2000  # 100% di 2000 kcal target
                weekday_days += 1
                logged += 1
            elif d.weekday() >= 5 and weekend_days < 2:
                qty = 1000  # 50% di 2000 kcal target
                weekend_days += 1
                logged += 1
            else:
                d -= timedelta(days=1)
                continue
            ClientMacroLogEntry.objects.create(
                assignment=assignment, log_date=d, food=self.food, quantity_g=qty,
            )
            d -= timedelta(days=1)

        result = adherence.compute_adherence(self.client_p)
        self.assertTrue(result['available'])
        self.assertTrue(result['reliable'])
        self.assertAlmostEqual(result['weekday_pct'], 100.0, delta=0.1)
        self.assertAlmostEqual(result['weekend_pct'], 50.0, delta=0.1)

    def test_weekly_pct_series_spans_wider_than_headline_window(self):
        assignment = self._macro_assignment(daily_kcal=2000)
        today = date.today()
        # Log ogni giorno per 8 settimane, sempre al 100% — copre più
        # dell'headline window_days=30 di default (serve per il forecast).
        for days_ago in range(1, 8 * 7):
            ClientMacroLogEntry.objects.create(
                assignment=assignment, log_date=today - timedelta(days=days_ago),
                food=self.food, quantity_g=2000,
            )
        result = adherence.compute_adherence(self.client_p)
        series = result['weekly_pct_series']
        self.assertGreater(len(series), 4)  # più delle ~4 settimane dell'headline a 30gg
        for _monday, pct in series:
            self.assertAlmostEqual(pct, 100.0, delta=0.1)
