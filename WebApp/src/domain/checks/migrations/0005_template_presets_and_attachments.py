import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('checks', '0004_assignedcheck_assignedcheckinstance'),
    ]

    operations = [
        migrations.AddField(
            model_name='questionnairetemplate',
            name='steps_config',
            field=models.JSONField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='questionnairetemplate',
            name='report_config',
            field=models.JSONField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='questionnairetemplate',
            name='preset_key',
            field=models.CharField(blank=True, db_index=True, max_length=50, null=True),
        ),
        migrations.AddField(
            model_name='questionnairetemplate',
            name='is_modified_preset',
            field=models.BooleanField(default=False),
        ),
        migrations.CreateModel(
            name='QuestionAttachment',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('question_id', models.CharField(max_length=100)),
                ('file_url', models.URLField(max_length=500)),
                ('file_name', models.CharField(max_length=255)),
                ('mime_type', models.CharField(blank=True, max_length=100)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('response', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='attachments', to='checks.questionnaireresponse')),
            ],
            options={'ordering': ['created_at']},
        ),
    ]
