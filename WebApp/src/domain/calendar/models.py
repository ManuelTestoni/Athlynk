from datetime import timedelta

from django.db import models

class Appointment(models.Model):
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='appointments')
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='appointments')
    appointment_type = models.CharField(max_length=50)
    title = models.CharField(max_length=200)
    description = models.TextField(null=True, blank=True)
    start_datetime = models.DateTimeField()
    duration_minutes = models.PositiveIntegerField(default=60)
    location = models.CharField(max_length=255, null=True, blank=True)
    meeting_url = models.URLField(max_length=500, null=True, blank=True)
    status = models.CharField(max_length=50)
    is_recurring = models.BooleanField(default=False)
    recurrence_rule = models.CharField(max_length=50, null=True, blank=True)  # settimanale, bisettimanale, mensile
    reminder_sent_at = models.DateTimeField(null=True, blank=True)
    cancellation_reason = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=['coach', 'start_datetime']),
            models.Index(fields=['client', 'start_datetime']),
            models.Index(fields=['status', 'start_datetime']),
        ]

    @property
    def end_datetime(self):
        """Derived end instant: start + duration. Read-only — set duration_minutes to change."""
        return self.start_datetime + timedelta(minutes=self.duration_minutes)

    def __str__(self):
        return f"{self.title} - {self.client}"
