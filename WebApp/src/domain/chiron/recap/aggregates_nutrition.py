"""Aggregazione nutrizione per il recap: wrapper sottile.

La logica vera (nuova, senza precedenti nel progetto) vive in
domain.nutrition.adherence — qui solo per uniformità con
aggregates_body/aggregates_training (un compute_* per dominio)."""

from domain.nutrition.adherence import compute_adherence


def compute_nutrition(client, window_days=30):
    return compute_adherence(client, window_days=window_days)
