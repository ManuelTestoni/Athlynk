from django.db import migrations, models


def backfill_log_date(apps, schema_editor):
    ClientMacroLogEntry = apps.get_model('nutrition', 'ClientMacroLogEntry')
    for entry in ClientMacroLogEntry.objects.filter(log_date__isnull=True).iterator():
        entry.log_date = entry.created_at.date()
        entry.save(update_fields=['log_date'])


class Migration(migrations.Migration):

    dependencies = [
        ('nutrition', '0010_dietday_target_carb_g_dietday_target_fat_g_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='clientmacrologentry',
            name='log_date',
            field=models.DateField(blank=True, db_index=True, null=True),
        ),
        migrations.AddIndex(
            model_name='clientmacrologentry',
            index=models.Index(fields=['assignment', 'log_date'], name='nutrition_c_assign_logdate_idx'),
        ),
        migrations.RunPython(backfill_log_date, migrations.RunPython.noop),
    ]
