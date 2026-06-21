# Generated for the «Calcolo Fabbisogni» tool: per-coach custom BMR formulas.

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0015_drop_orphan_timeline'),
    ]

    operations = [
        migrations.AddField(
            model_name='coachprofile',
            name='custom_bmr_formulas',
            field=models.JSONField(blank=True, default=list),
        ),
    ]
