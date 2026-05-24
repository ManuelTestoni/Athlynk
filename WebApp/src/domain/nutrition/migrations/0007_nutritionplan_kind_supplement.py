from django.db import migrations, models


def backfill_plan_kind(apps, schema_editor):
    """Any plan that already has DietDay children is WEEKLY; otherwise DAILY."""
    NutritionPlan = apps.get_model('nutrition', 'NutritionPlan')
    DietDay = apps.get_model('nutrition', 'DietDay')

    weekly_plan_ids = set(
        DietDay.objects.values_list('plan_id', flat=True).distinct()
    )
    if weekly_plan_ids:
        NutritionPlan.objects.filter(id__in=weekly_plan_ids).update(plan_kind='WEEKLY')
    NutritionPlan.objects.exclude(id__in=weekly_plan_ids).update(plan_kind='DAILY')


def reverse_noop(apps, schema_editor):
    """Field is dropped on reverse; nothing to undo at the data level."""
    pass


class Migration(migrations.Migration):

    dependencies = [
        ('nutrition', '0006_nutritionfolder_nutritionplan_folder'),
    ]

    operations = [
        migrations.AddField(
            model_name='nutritionplan',
            name='plan_kind',
            field=models.CharField(
                choices=[('DAILY', 'Giornaliero'), ('WEEKLY', 'Settimanale')],
                default='DAILY',
                max_length=10,
            ),
        ),
        migrations.AddField(
            model_name='nutritionplan',
            name='supplement_sheet',
            field=models.OneToOneField(
                blank=True,
                null=True,
                on_delete=models.deletion.SET_NULL,
                related_name='nutrition_plan',
                to='nutrition.supplementsheet',
            ),
        ),
        migrations.RunPython(backfill_plan_kind, reverse_noop),
    ]
