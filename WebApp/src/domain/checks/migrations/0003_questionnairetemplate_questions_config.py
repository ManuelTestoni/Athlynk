from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('checks', '0002_questionnaireresponse_coach_feedback_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='questionnairetemplate',
            name='questions_config',
            field=models.JSONField(blank=True, null=True),
        ),
    ]
