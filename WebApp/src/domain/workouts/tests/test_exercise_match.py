"""Matching of Italian free text against the English exercise catalogue.

Coaches upload Italian documents; `Exercise.name` comes from an English dataset.
These tests pin the two properties that matter for the import flow:

  1. common Italian phrasings resolve to *a* catalogue row, and
  2. when the coach names an implement, the row we pick uses that implement —
     and if no candidate does, we return nothing rather than a confident wrong
     answer, so the row surfaces for review.

(2) is the regression that motivated the rewrite: "panca piana con bilanciere"
used to return "band bench press" at 'exact' confidence, which saved silently.
"""

from django.test import TestCase

from domain.workouts.imports.exercise_match import (
    _equipment_by_label,
    _requested_equipment,
    best_match,
)
from domain.workouts.models import Equipment, Exercise


class ExerciseMatchTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        # The taxonomy is seeded by migration 0009, so reuse whatever is already
        # there and only fill gaps — `wger_id` is unique and NOT NULL, hence the
        # negative ids for anything we have to invent.
        def equipment(name_it, name_en=''):
            obj = Equipment.objects.filter(name_it=name_it).first()
            if obj:
                return obj
            equipment.next_id -= 1
            return Equipment.objects.create(
                name_it=name_it, name_en=name_en, wger_id=equipment.next_id)
        equipment.next_id = 0

        cls.barbell = equipment('Bilanciere')
        cls.dumbbell = equipment('Manubrio')
        cls.cable = equipment('Cavo', 'cable')
        cls.band = equipment('Elastico')
        cls.bodyweight = equipment('Corpo libero')
        # Known implement with no exercise on file — see the unresolved test.
        cls.kettlebell = equipment('Kettlebell')

        cls.catalogue = {}
        for name, equipment in [
            ('barbell bench press', cls.barbell),
            ('dumbbell bench press', cls.dumbbell),
            ('band bench press', cls.band),
            ('barbell bent over row', cls.barbell),
            ('dumbbell lunge', cls.dumbbell),
            ('barbell lunge', cls.barbell),
            ('barbell curl', cls.barbell),
            ('dumbbell lateral raise', cls.dumbbell),
            ('cable lateral raise', cls.cable),
            ('cable decline fly', cls.cable),
            ('pull-up', cls.bodyweight),
            ('barbell deadlift', cls.barbell),
        ]:
            ex = Exercise.objects.create(name=name, slug=name.replace(' ', '-'))
            ex.equipment.set([equipment])
            cls.catalogue[name] = ex

        # The label→id map is cached process-wide; drop it so this fixture wins.
        _equipment_by_label.cache_clear()

    @classmethod
    def tearDownClass(cls):
        _equipment_by_label.cache_clear()
        super().tearDownClass()

    # ── Equipment is read from the Italian text ────────────────────────────

    def test_requested_equipment_reads_italian_implements(self):
        self.assertEqual(_requested_equipment('Panca piana con bilanciere'), {self.barbell.id})
        self.assertEqual(_requested_equipment('Affondi con manubri'), {self.dumbbell.id})
        self.assertEqual(_requested_equipment('Croci ai cavi'), {self.cable.id})

    def test_panca_alone_is_not_an_implement(self):
        """'panca piana' names the movement (bench press), not a bench."""
        self.assertEqual(_requested_equipment('Panca piana'), set())

    # ── The regression: implement decides between same-movement rows ───────

    def test_barbell_and_dumbbell_bench_press_do_not_collide(self):
        barbell, _, conf, _ = best_match(
            'Panca piana con bilanciere', name_en='barbell bench press')
        self.assertEqual(barbell['name'], 'barbell bench press')
        self.assertEqual(conf, 'exact')

        dumbbell, _, conf, _ = best_match(
            'Panca piana con manubri', name_en='dumbbell bench press')
        self.assertEqual(dumbbell['name'], 'dumbbell bench press')
        self.assertEqual(conf, 'exact')

    def test_wrong_implement_never_wins(self):
        best, _, _, _ = best_match('Affondi con manubri', name_en='dumbbell lunge')
        self.assertEqual(best['name'], 'dumbbell lunge')

    def test_unavailable_implement_is_left_unresolved(self):
        """Kettlebell bench press isn't in the catalogue: better none than 'band'."""
        best, candidates, conf, _ = best_match(
            'Panca piana con kettlebell', name_en='kettlebell bench press')
        self.assertIsNone(best)
        self.assertNotEqual(conf, 'exact')
        self.assertTrue(candidates, 'the coach still needs something to pick from')

    # ── Italian coverage ──────────────────────────────────────────────────

    def test_italian_names_resolve(self):
        cases = [
            ('Panca piana con bilanciere', 'barbell bench press'),
            ('Rematore con bilanciere', 'barbell bent over row'),
            ('Affondi con manubri', 'dumbbell lunge'),
            ('Curl con bilanciere', 'barbell curl'),
            ('Alzate laterali con manubri', 'dumbbell lateral raise'),
            ('Croci ai cavi', 'cable fly'),
            ('Trazioni alla sbarra', 'pull-up'),
            ('Stacco da terra', 'deadlift'),
        ]
        unresolved = [
            italian for italian, english in cases
            if best_match(italian, name_en=english)[0] is None
        ]
        self.assertEqual(unresolved, [])

    def test_raw_name_alone_still_matches_without_translation(self):
        """name_en is an aid, not a dependency — an extractor that omits it
        must not make matching worse than it was."""
        best, _, _, _ = best_match('Curl con bilanciere')
        self.assertIsNotNone(best)
        self.assertEqual(best['name'], 'barbell curl')

    def test_bad_translation_cannot_beat_a_good_raw_match(self):
        best, _, _, _ = best_match('Curl con bilanciere', name_en='cable decline fly')
        self.assertEqual(best['name'], 'barbell curl')

    # ── Aliases participate in matching ───────────────────────────────────

    def test_aliases_are_searched(self):
        ex = Exercise.objects.create(name='hip thrust', slug='hip-thrust',
                                     aliases=['ponte per glutei'])
        ex.equipment.set([self.barbell])
        best, _, _, _ = best_match('Ponte per glutei')
        self.assertIsNotNone(best)
        self.assertEqual(best['id'], ex.id)

    def test_empty_input_is_handled(self):
        self.assertEqual(best_match(''), (None, [], 'none', 'none'))
        self.assertEqual(best_match('   '), (None, [], 'none', 'none'))
