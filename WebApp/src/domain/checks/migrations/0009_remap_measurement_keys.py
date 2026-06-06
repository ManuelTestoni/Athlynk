"""Lossy remap of legacy circumference/skinfold keys to the new ISAK vocabulary.

Old fixed keys become the catalog keys used by the `antropometria` question type.
Keys without an ISAK equivalent (`shoulders` circ, `chest` skinfold) are dropped.
"""
from django.db import migrations

from domain.checks.anthropometry import LEGACY_CIRC_MAP, LEGACY_SKIN_MAP


def _remap(values, mapping):
    if not isinstance(values, dict):
        return values, False
    out, changed = {}, False
    for key, val in values.items():
        if key in mapping:
            changed = True
            new_key = mapping[key]
            if new_key is None:        # no ISAK equivalent → drop
                continue
            # don't clobber a value already present under the new key
            if val not in (None, '') or new_key not in out:
                out[new_key] = val
        else:
            out.setdefault(key, val)
    return out, changed


def forwards(apps, schema_editor):
    Response = apps.get_model('checks', 'QuestionnaireResponse')
    for r in Response.objects.all().iterator():
        circ, c1 = _remap(r.body_circumferences, LEGACY_CIRC_MAP)
        skin, c2 = _remap(r.skinfolds, LEGACY_SKIN_MAP)
        if c1 or c2:
            r.body_circumferences = circ
            r.skinfolds = skin
            r.save(update_fields=['body_circumferences', 'skinfolds'])


def backwards(apps, schema_editor):
    Response = apps.get_model('checks', 'QuestionnaireResponse')
    inv_circ = {v: k for k, v in LEGACY_CIRC_MAP.items() if v}
    inv_skin = {v: k for k, v in LEGACY_SKIN_MAP.items() if v}
    for r in Response.objects.all().iterator():
        circ, c1 = _remap(r.body_circumferences, inv_circ)
        skin, c2 = _remap(r.skinfolds, inv_skin)
        if c1 or c2:
            r.body_circumferences = circ
            r.skinfolds = skin
            r.save(update_fields=['body_circumferences', 'skinfolds'])


class Migration(migrations.Migration):

    dependencies = [
        ('checks', '0008_checkfolder_questionnairetemplate_folder'),
    ]

    operations = [
        migrations.RunPython(forwards, backwards),
    ]
