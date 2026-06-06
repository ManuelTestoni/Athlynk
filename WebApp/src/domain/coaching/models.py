from django.db import models

class CoachingRelationship(models.Model):
    RELATIONSHIP_TYPES = [
        ('FULL', 'Full (Coach)'),
        ('WORKOUT', 'Workout only'),
        ('NUTRITION', 'Nutrition only'),
    ]

    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='coaching_relationships_as_coach')
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='coaching_relationships_as_client')
    status = models.CharField(max_length=50) # Es. ACTIVE, INACTIVE, PENDING
    start_date = models.DateField()
    end_date = models.DateField(null=True, blank=True)
    relationship_type = models.CharField(max_length=20, choices=RELATIONSHIP_TYPES, null=True, blank=True)
    internal_notes = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=['coach', 'status']),
            models.Index(fields=['client', 'status']),
        ]

    def __str__(self):
        return f"{self.coach} - {self.client} ({self.status})"


class CoachingPhase(models.Model):
    """A free-text note placed on the client's timeline by the professional,
    spanning a period (start_date + duration) — e.g. a cut/bulk block."""
    DURATION_UNITS = [
        ('WEEKS', 'Settimane'),
        ('MONTHS', 'Mesi'),
    ]

    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='coaching_phases')
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='coaching_phases')
    title = models.CharField(max_length=120)
    note = models.TextField(blank=True, default='')
    start_date = models.DateField()
    duration_value = models.PositiveIntegerField()
    duration_unit = models.CharField(max_length=10, choices=DURATION_UNITS, default='WEEKS')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['start_date']
        indexes = [
            models.Index(fields=['coach', 'client']),
        ]

    @property
    def end_date(self):
        from datetime import timedelta
        if self.duration_unit == 'MONTHS':
            month = self.start_date.month - 1 + self.duration_value
            year = self.start_date.year + month // 12
            month = month % 12 + 1
            import calendar
            day = min(self.start_date.day, calendar.monthrange(year, month)[1])
            return self.start_date.replace(year=year, month=month, day=day)
        return self.start_date + timedelta(weeks=self.duration_value)

    def __str__(self):
        return f"{self.title} ({self.client})"

class ClientAnamnesis(models.Model):
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='anamnesis')
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.SET_NULL, null=True, blank=True, related_name='client_anamnesis')
    anamnesis_date = models.DateField()
    age = models.IntegerField(null=True, blank=True)
    weight_kg = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    height_cm = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    medical_history = models.TextField(null=True, blank=True)
    medications = models.TextField(null=True, blank=True)
    injuries = models.TextField(null=True, blank=True)
    allergies = models.TextField(null=True, blank=True)
    intolerances = models.TextField(null=True, blank=True)
    lifestyle_notes = models.TextField(null=True, blank=True)
    sleep_quality = models.CharField(max_length=100, null=True, blank=True)
    stress_level = models.CharField(max_length=100, null=True, blank=True)
    food_habits = models.TextField(null=True, blank=True)
    weight_history = models.TextField(null=True, blank=True)
    path_goal = models.TextField(null=True, blank=True)
    professional_notes = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Anamnesis for {self.client} on {self.anamnesis_date}"
