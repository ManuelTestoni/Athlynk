import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0012_devicetoken'),
        ('checks', '0007_assignedcheck_checks_assi_client__c9a8da_idx_and_more'),
    ]

    operations = [
        migrations.CreateModel(
            name='CheckFolder',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('title', models.CharField(max_length=120)),
                ('label_text', models.CharField(blank=True, default='', max_length=40)),
                ('label_color', models.CharField(blank=True, default='', max_length=20)),
                ('order', models.PositiveIntegerField(default=0)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('coach', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='check_folders', to='accounts.coachprofile')),
            ],
            options={
                'ordering': ['order', 'title'],
                'unique_together': {('coach', 'title')},
            },
        ),
        migrations.AddField(
            model_name='questionnairetemplate',
            name='folder',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='templates', to='checks.checkfolder'),
        ),
    ]
