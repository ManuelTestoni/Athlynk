"""Regression tests for the two Chiron diet-import completion bugs.

Both made food-rich plans (but not macro-only plans) fail extraction, which — with
the status stored only in a fail-open Redis key — surfaced to the coach as an
endless spinner / "Sessione scaduta":

  1. The whole-document LLM call had a 30s timeout, but a full weekly food grid
     needs ~80-90s on gpt-oss:120b → guaranteed APITimeoutError.
  2. The LLM emits `unit: null` (or a synonym) for foods listed without a unit;
     the strict `Unit` Literal rejected every one → a 7-day grid produced 77
     validation errors → the whole extraction blew up.
"""

from unittest import mock

from django.test import SimpleTestCase

from domain.nutrition.schemas import FoodEntry, SubstitutionEntry, DietExtraction


class UnitCoercionTests(SimpleTestCase):
    def test_null_unit_coerced_to_grams(self):
        # The exact production failure: explicit null (not an absent key).
        self.assertEqual(FoodEntry(name='mela', unit=None).unit, 'g')
        self.assertEqual(SubstitutionEntry(name='pane', unit=None).unit, 'g')

    def test_absent_unit_defaults_to_grams(self):
        self.assertEqual(FoodEntry(name='riso').unit, 'g')

    def test_synonyms_are_normalized(self):
        self.assertEqual(FoodEntry(name='pane', unit='grammi').unit, 'g')
        self.assertEqual(FoodEntry(name='latte', unit='millilitri').unit, 'ml')
        self.assertEqual(FoodEntry(name='olio', unit='cucchiaio').unit, 'tbsp')
        self.assertEqual(FoodEntry(name='sale', unit='cucchiaino').unit, 'tsp')
        self.assertEqual(FoodEntry(name='uovo', unit='pezzo').unit, 'portion')

    def test_valid_units_pass_through(self):
        for u in ('g', 'ml', 'portion', 'tbsp', 'tsp'):
            self.assertEqual(FoodEntry(name='x', unit=u).unit, u)

    def test_unknown_unit_falls_back_to_grams(self):
        self.assertEqual(FoodEntry(name='x', unit='blorp').unit, 'g')

    def test_full_weekly_grid_with_null_units_validates(self):
        """Shrunk repro of the 77-error blow-up: a nested doc where every food has
        a null unit must now validate cleanly instead of raising."""
        doc = {
            'days': [
                {
                    'day_of_week': d,
                    'meals': [
                        {'meal_type': 'LUNCH',
                         'foods': [{'name': 'pasta', 'quantity': 80, 'unit': None},
                                   {'name': 'pollo', 'quantity': 150, 'unit': None}]},
                    ],
                }
                for d in ('MONDAY', 'TUESDAY', 'WEDNESDAY')
            ]
        }
        parsed = DietExtraction(**doc)  # must not raise
        units = [f.unit for day in parsed.days for m in day.meals for f in m.foods]
        self.assertEqual(set(units), {'g'})


class FastPathTimeoutTests(SimpleTestCase):
    """The whole-document call must get a generous timeout; only the tiny
    macro-only call keeps the short one."""

    def _timeout_for(self, is_macro):
        from domain.nutrition import excel_importer
        from domain.shared.doc_structure import DocStructure

        structure = DocStructure(layout='macro_daily' if is_macro else 'food_weekly')
        captured = {}

        class _FakeResp:
            content = '{"days": []}'

        def _fake_build(max_tokens=4000, timeout=30):
            captured['timeout'] = timeout
            llm = mock.MagicMock()
            llm.invoke.return_value = _FakeResp()
            return llm

        with mock.patch.object(excel_importer, 'build_extraction_llm', _fake_build):
            excel_importer.extract_diet_with_ai('grid text', 'Piano', structure=structure)
        return captured['timeout']

    def test_whole_document_call_gets_large_timeout(self):
        self.assertGreaterEqual(self._timeout_for(is_macro=False), 90)

    def test_macro_only_call_keeps_short_timeout(self):
        self.assertLessEqual(self._timeout_for(is_macro=True), 30)
