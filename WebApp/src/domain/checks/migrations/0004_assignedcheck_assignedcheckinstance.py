import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0001_initial'),
        ('checks', '0003_questionnairetemplate_questions_config'),
    ]

    operations = [
        migrations.CreateModel(
            name='AssignedCheck',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('snapshot_config', models.JSONField(blank=True, null=True)),
                ('recurrence_type', models.CharField(choices=[('once', 'Una volta sola'), ('weekly', 'Giorno della settimana'), ('monthly', 'Giorno del mese'), ('end_program', 'Fine programma')], default='once', max_length=20)),
                ('weekly_day', models.IntegerField(blank=True, null=True)),
                ('monthly_day', models.IntegerField(blank=True, null=True)),
                ('duration_hours', models.IntegerField(default=72)),
                ('notes', models.TextField(blank=True)),
                ('is_active', models.BooleanField(default=True)),
                ('assigned_at', models.DateTimeField(auto_now_add=True)),
                ('client', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='assigned_checks', to='accounts.clientprofile')),
                ('coach', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='sent_checks', to='accounts.coachprofile')),
                ('template', models.ForeignKey(null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='assignments', to='checks.questionnairetemplate')),
            ],
            options={'ordering': ['-assigned_at']},
        ),
        migrations.CreateModel(
            name='AssignedCheckInstance',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('due_date', models.DateField()),
                ('expires_at', models.DateTimeField()),
                ('status', models.CharField(choices=[('pending', 'Da compilare'), ('completed', 'Completato'), ('expired', 'Scaduto')], default='pending', max_length=20)),
                ('notified_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('assignment', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='instances', to='checks.assignedcheck')),
                ('response', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, to='checks.questionnaireresponse')),
            ],
            options={'ordering': ['-due_date']},
        ),
    ]
