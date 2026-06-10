from django.core.management.base import BaseCommand, CommandError

from domain.analytics.ml import TARGETS


class Command(BaseCommand):
    help = ("Train + register an XGBoost model for a target. Run weekly/manually. "
            "Cold start: use --bootstrap (or target risk_class) to exercise the "
            "pipeline on rule-based pseudo-labels until real history exists.")

    def add_arguments(self, parser):
        parser.add_argument('--target', type=str, default='risk_class',
                            choices=list(TARGETS), help='Prediction target.')
        parser.add_argument('--bootstrap', action='store_true',
                            help='Force bootstrap (pseudo-label) training.')

    def handle(self, *args, **options):
        try:
            from domain.analytics.ml.train import train
        except Exception as exc:
            raise CommandError(f'ML deps unavailable: {exc}')

        target = options['target']
        try:
            mv = train(target, bootstrap=options['bootstrap'])
        except RuntimeError as exc:
            raise CommandError(str(exc))

        flag = 'BOOTSTRAP' if mv.is_bootstrap else 'TRAINED'
        self.stdout.write(self.style.SUCCESS(
            f'[{flag}] {target} v={mv.version} '
            f'(train={mv.n_train}, valid={mv.n_valid}) metrics={mv.metrics}'))
