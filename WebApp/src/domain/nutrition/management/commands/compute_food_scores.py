"""Management command: bulk-recompute the query-independent "genericity score"
for every Food row and store it in Food.genericity_score. New foods get their
score automatically via the Food pre_save signal, so you only need this for a
full recompute (e.g. after changing the weights in domain/nutrition/scoring.py,
or a large import done with bulk operations that bypass signals):

    python manage.py compute_food_scores            # compute + save
    python manage.py compute_food_scores --dry-run  # analyze + print, no save

Higher score = more generic = ranks higher. Scoring logic lives in
domain/nutrition/scoring.py (shared with the signal).
"""
from django.core.management.base import BaseCommand

from domain.nutrition.models import Food
from domain.nutrition.scoring import discover_brands, score_name


class Command(BaseCommand):
    help = "Bulk-recompute and store Food.genericity_score for all foods."

    def add_arguments(self, parser):
        parser.add_argument('--dry-run', action='store_true',
                            help="Analyze and print, do not write to DB.")
        parser.add_argument('--show', type=int, default=15,
                            help="How many top/bottom rows to print.")

    def handle(self, *args, **opts):
        foods = list(Food.objects.all().only('id', 'nome_alimento'))
        names = [f.nome_alimento for f in foods]

        brands = discover_brands(names)
        self.stdout.write(self.style.MIGRATE_HEADING(
            f"Detected {len(brands)} brand parentheticals (top 20):"))
        for brand, n in brands.most_common(20):
            self.stdout.write(f"  ({brand})  ×{n}")

        for f in foods:
            f.genericity_score = score_name(f.nome_alimento)

        ranked = sorted(foods, key=lambda f: f.genericity_score)
        show = opts['show']
        self.stdout.write(self.style.MIGRATE_HEADING(
            f"\nLowest {show} (penalized):"))
        for f in ranked[:show]:
            self.stdout.write(f"  {f.genericity_score:+6.2f}  {f.nome_alimento}")
        self.stdout.write(self.style.MIGRATE_HEADING(
            f"\nHighest {show} (most generic):"))
        for f in ranked[-show:][::-1]:
            self.stdout.write(f"  {f.genericity_score:+6.2f}  {f.nome_alimento}")

        if opts['dry_run']:
            self.stdout.write(self.style.WARNING("\n--dry-run: nothing saved."))
            return

        Food.objects.bulk_update(foods, ['genericity_score'], batch_size=500)
        self.stdout.write(self.style.SUCCESS(
            f"\nSaved genericity_score for {len(foods)} foods."))
