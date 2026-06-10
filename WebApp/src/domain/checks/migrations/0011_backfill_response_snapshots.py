"""Backfill questions/steps snapshot sulle risposte esistenti.

Priorità: snapshot_config dell'assignment (config al momento dell'assegnazione)
quando la risposta proviene da un AssignedCheckInstance; altrimenti la config
corrente del template (migliore approssimazione disponibile).
"""

from django.db import migrations


def backfill(apps, schema_editor):
    QuestionnaireResponse = apps.get_model('checks', 'QuestionnaireResponse')
    AssignedCheckInstance = apps.get_model('checks', 'AssignedCheckInstance')

    snap_by_response = {
        inst.response_id: inst.assignment
        for inst in AssignedCheckInstance.objects
        .select_related('assignment', 'assignment__template')
        .filter(response__isnull=False)
    }

    batch = []
    qs = QuestionnaireResponse.objects.select_related('questionnaire_template') \
        .filter(questions_snapshot__isnull=True)
    for resp in qs.iterator():
        assignment = snap_by_response.get(resp.id)
        if assignment is not None and assignment.snapshot_config:
            resp.questions_snapshot = assignment.snapshot_config
            tpl = assignment.template or resp.questionnaire_template
        else:
            tpl = resp.questionnaire_template
            resp.questions_snapshot = (tpl.questions_config or []) if tpl else []
        resp.steps_snapshot = (tpl.steps_config or []) if tpl else []
        batch.append(resp)
        if len(batch) >= 500:
            QuestionnaireResponse.objects.bulk_update(
                batch, ['questions_snapshot', 'steps_snapshot'])
            batch = []
    if batch:
        QuestionnaireResponse.objects.bulk_update(
            batch, ['questions_snapshot', 'steps_snapshot'])


class Migration(migrations.Migration):

    dependencies = [
        ('checks', '0010_questionnaireresponse_questions_snapshot_and_more'),
    ]

    operations = [
        migrations.RunPython(backfill, migrations.RunPython.noop),
    ]
