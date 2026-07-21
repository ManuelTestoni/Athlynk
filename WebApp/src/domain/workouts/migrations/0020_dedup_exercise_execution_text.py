"""Deduplicate the exercise execution text.

Every exercise historically stored the same instructional content twice:
`Exercise.description` (prose) and `Exercise.instruction_steps` (step list).
We keep `instruction_steps` as the single source of truth. For any exercise
that has a `description` but no `instruction_steps`, backfill the steps from
the prose; then clear `description` so the duplicate is gone. Non-destructive
to the column itself (kept for back-compat) — only the data is de-duplicated.
"""
import re

from django.db import migrations


def _split_prose_to_steps(text):
    if not text:
        return []
    raw = [ln.strip() for ln in str(text).splitlines() if ln.strip()]
    if len(raw) <= 1:
        raw = [s.strip() for s in re.split(r'(?<=[.!?])\s+', str(text)) if s.strip()]
    return raw


def forwards(apps, schema_editor):
    Exercise = apps.get_model('workouts', 'Exercise')
    for ex in Exercise.objects.all().only('id', 'description', 'instruction_steps').iterator():
        steps = ex.instruction_steps or []
        if not steps and ex.description:
            steps = _split_prose_to_steps(ex.description)
        # Keep instruction_steps as the single source; drop the duplicated prose.
        changed = False
        if steps != (ex.instruction_steps or []):
            ex.instruction_steps = steps
            changed = True
        if ex.description:
            ex.description = None
            changed = True
        if changed:
            ex.save(update_fields=['instruction_steps', 'description'])


def backwards(apps, schema_editor):
    # Irreversible in a lossless way (the prose was discarded); no-op.
    pass


class Migration(migrations.Migration):

    dependencies = [
        ('workouts', '0019_exercise_dataset_id_exercise_demo_gif_and_more'),
    ]

    operations = [
        migrations.RunPython(forwards, backwards),
    ]
