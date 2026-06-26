"""Unit checks for the free-text supplement helpers and quick-measurement check
naming. Pure functions — no DB needed."""

from types import SimpleNamespace
from django.test import SimpleTestCase

from config.views_nutrition import _parse_supplement_items, _clean_unit
from config.views_check.assignments import _latest_check_name, _json_filled


class SupplementHelperTests(SimpleTestCase):
    def test_clean_unit_whitelist(self):
        self.assertEqual(_clean_unit('mg'), 'mg')
        self.assertEqual(_clean_unit('g'), 'g')
        self.assertEqual(_clean_unit('cps'), 'cps')
        self.assertEqual(_clean_unit('kg'), '')      # not allowed → blank
        self.assertEqual(_clean_unit(None), '')

    def test_parse_skips_nameless_and_trims(self):
        items = _parse_supplement_items([
            {'name': '  Creatina ', 'quantity': ' 5 ', 'unit': 'g', 'timing': 'Post Workout', 'notes': ''},
            {'name': '   ', 'quantity': '1'},          # no name → skipped
            {'name': 'Omega 3', 'unit': 'kg'},         # bad unit → blank
        ])
        self.assertEqual(len(items), 2)
        self.assertEqual(items[0]['name'], 'Creatina')
        self.assertEqual(items[0]['quantity'], '5')
        self.assertEqual(items[1]['unit'], '')


class CheckNameTests(SimpleTestCase):
    def test_json_filled_dict_and_str(self):
        self.assertFalse(_json_filled(None))
        self.assertFalse(_json_filled('{}'))
        self.assertFalse(_json_filled({}))
        self.assertTrue(_json_filled({'tricep': '8'}))
        self.assertTrue(_json_filled('{"tricep": "8"}'))

    def test_quick_measurement_subtype(self):
        skin = SimpleNamespace(latest_qtype='quick_measurement', latest_title='Misurazione rapida',
                               latest_skinfolds={'tricep': '8'}, latest_circumferences=None)
        self.assertEqual(_latest_check_name(skin), 'Misurazione Singola - Pliche')

        circ = SimpleNamespace(latest_qtype='quick_measurement', latest_title='Misurazione rapida',
                               latest_skinfolds=None, latest_circumferences={'waist': '80'})
        self.assertEqual(_latest_check_name(circ), 'Misurazione Singola - Circonferenze')

        weight = SimpleNamespace(latest_qtype='quick_measurement', latest_title='Misurazione rapida',
                                 latest_skinfolds=None, latest_circumferences=None)
        self.assertEqual(_latest_check_name(weight), 'Misurazione Singola - Peso')

    def test_named_check_uses_title(self):
        named = SimpleNamespace(latest_qtype='custom_check', latest_title='Bioimpedenza',
                                latest_skinfolds=None, latest_circumferences=None)
        self.assertEqual(_latest_check_name(named), 'Bioimpedenza')
