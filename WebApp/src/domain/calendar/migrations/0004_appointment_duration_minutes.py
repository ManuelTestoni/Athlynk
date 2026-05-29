from django.db import migrations, models


def end_to_duration(apps, schema_editor):
    Appointment = apps.get_model('calendar', 'Appointment')
    for appt in Appointment.objects.all().iterator():
        delta = (appt.end_datetime - appt.start_datetime).total_seconds() / 60
        appt.duration_minutes = max(1, int(round(delta)))
        appt.save(update_fields=['duration_minutes'])


def duration_to_end(apps, schema_editor):
    from datetime import timedelta
    Appointment = apps.get_model('calendar', 'Appointment')
    for appt in Appointment.objects.all().iterator():
        appt.end_datetime = appt.start_datetime + timedelta(minutes=appt.duration_minutes or 60)
        appt.save(update_fields=['end_datetime'])


class Migration(migrations.Migration):

    dependencies = [
        ('calendar', '0003_appointment_calendar_ap_coach_i_c32a3a_idx_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='appointment',
            name='duration_minutes',
            field=models.PositiveIntegerField(default=60),
        ),
        migrations.RunPython(end_to_duration, duration_to_end),
        migrations.RemoveField(
            model_name='appointment',
            name='end_datetime',
        ),
    ]
