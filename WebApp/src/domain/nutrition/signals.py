"""Keep Food.genericity_score in sync on every per-row save.

pre_save sets the field before the row is written, so there is no second save
and no recursion. bulk_create / bulk_update do NOT fire signals — use the
compute_food_scores command for those bulk paths.
"""
from django.db.models.signals import pre_save
from django.dispatch import receiver

from domain.nutrition.models import Food
from domain.nutrition.scoring import score_name


@receiver(pre_save, sender=Food)
def set_food_genericity_score(sender, instance, **kwargs):
    instance.genericity_score = score_name(instance.nome_alimento)
