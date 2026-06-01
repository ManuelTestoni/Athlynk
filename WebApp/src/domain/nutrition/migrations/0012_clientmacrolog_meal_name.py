from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('nutrition', '0011_clientmacrolog_log_date'),
    ]

    operations = [
        migrations.AddField(
            model_name='clientmacrologentry',
            name='meal_name',
            field=models.CharField(blank=True, max_length=100, null=True),
        ),
    ]
