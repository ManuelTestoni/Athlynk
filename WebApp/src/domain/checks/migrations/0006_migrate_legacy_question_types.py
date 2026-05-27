from django.db import migrations


TYPE_REMAP = {
    'tempo':  'aperta',
    'range':  'metrica',
    'elenco': 'radio',
}

DEFAULT_STEP_LABELS = {
    1: ('s_misurazioni', 'Misurazioni', 'ph-ruler'),
    2: ('s_benessere',   'Benessere',   'ph-smiley'),
    3: ('s_note',        'Note',        'ph-note-pencil'),
    4: ('s_foto',        'Foto',        'ph-camera'),
}


def _remap_question(q: dict) -> dict:
    """Mutate a question dict in place to align with the new schema."""
    old_type = q.get('type')
    if old_type in TYPE_REMAP:
        new_type = TYPE_REMAP[old_type]
        q['type'] = new_type
        # tempo had no extras; range had rangeMin/rangeMax → for metrica we drop them
        if old_type == 'range':
            q.pop('rangeMin', None)
            q.pop('rangeMax', None)
            q.setdefault('unit', '')
    # ensure required exists
    q.setdefault('required', False)
    # ensure report_visible exists
    q.setdefault('report_visible', True)
    return q


def _derive_steps(questions: list) -> tuple[list, dict]:
    """Return (steps_config, int_step → step_id map)."""
    used_int_steps = sorted({q.get('step', 1) for q in questions if isinstance(q.get('step'), int)})
    if not used_int_steps:
        used_int_steps = [1]
    steps = []
    mapping = {}
    for i, n in enumerate(used_int_steps, start=1):
        if n in DEFAULT_STEP_LABELS:
            sid, label, icon = DEFAULT_STEP_LABELS[n]
        else:
            sid, label, icon = f's_{i}', f'Step {i}', 'ph-list'
        steps.append({'id': sid, 'label': label, 'icon': icon})
        mapping[n] = sid
    return steps, mapping


def _migrate_questions_list(questions):
    if not isinstance(questions, list):
        return questions, None
    steps, step_map = _derive_steps(questions)
    out = []
    for q in questions:
        if not isinstance(q, dict):
            out.append(q)
            continue
        q = dict(q)
        _remap_question(q)
        if 'step_id' not in q:
            int_step = q.get('step', 1) if isinstance(q.get('step'), int) else 1
            q['step_id'] = step_map.get(int_step, steps[0]['id'])
        out.append(q)
    return out, steps


def forwards(apps, schema_editor):
    QT = apps.get_model('checks', 'QuestionnaireTemplate')
    AC = apps.get_model('checks', 'AssignedCheck')

    for tpl in QT.objects.all():
        cfg = tpl.questions_config
        if not cfg:
            continue
        new_questions, new_steps = _migrate_questions_list(cfg)
        tpl.questions_config = new_questions
        if new_steps and not tpl.steps_config:
            tpl.steps_config = new_steps
        tpl.save(update_fields=['questions_config', 'steps_config'])

    for asn in AC.objects.all():
        snap = asn.snapshot_config
        if not snap:
            continue
        new_questions, _ = _migrate_questions_list(snap)
        asn.snapshot_config = new_questions
        asn.save(update_fields=['snapshot_config'])


def backwards(apps, schema_editor):
    # No-op: the remap is lossy; cannot reliably restore tempo/range/elenco.
    pass


class Migration(migrations.Migration):

    dependencies = [
        ('checks', '0005_template_presets_and_attachments'),
    ]

    operations = [
        migrations.RunPython(forwards, backwards),
    ]
