from django.db import models
from django.utils import timezone

class Exercise(models.Model):
    name = models.CharField(max_length=200)
    slug = models.SlugField(max_length=220, unique=True)
    video_url = models.URLField(max_length=500, null=True, blank=True)
    difficulty_level = models.CharField(max_length=50, null=True, blank=True)
    target_muscle_group = models.CharField(max_length=100, null=True, blank=True)
    primary_muscle = models.CharField(max_length=100, null=True, blank=True)
    secondary_muscle = models.CharField(max_length=100, null=True, blank=True)
    equipment = models.CharField(max_length=100, null=True, blank=True)
    movement_pattern_1 = models.CharField(max_length=100, null=True, blank=True)
    movement_pattern_2 = models.CharField(max_length=100, null=True, blank=True)
    body_region = models.CharField(max_length=50, null=True, blank=True)
    exercise_classification = models.CharField(max_length=100, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.name

class WorkoutPlan(models.Model):
    STATUS_DRAFT = 'DRAFT'
    STATUS_TEMPLATE = 'TEMPLATE'
    STATUS_ACTIVE = 'ACTIVE'
    STATUS_CHOICES = [
        (STATUS_DRAFT, 'Bozza'),
        (STATUS_TEMPLATE, 'Template'),
        (STATUS_ACTIVE, 'Attiva'),
    ]

    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='workout_plans')
    title = models.CharField(max_length=200)
    description = models.TextField(null=True, blank=True)
    level = models.CharField(max_length=50, null=True, blank=True)
    goal = models.CharField(max_length=200, null=True, blank=True)
    is_template = models.BooleanField(default=False)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_DRAFT)
    frequency_per_week = models.IntegerField(null=True, blank=True)
    duration_weeks = models.IntegerField(null=True, blank=True)
    last_step = models.IntegerField(default=1)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.title

class WorkoutDay(models.Model):
    workout_plan = models.ForeignKey(WorkoutPlan, on_delete=models.CASCADE, related_name='days')
    day_order = models.IntegerField()
    day_name = models.CharField(max_length=100, null=True, blank=True)
    title = models.CharField(max_length=200, null=True, blank=True)
    focus_area = models.CharField(max_length=200, null=True, blank=True)
    day_type = models.CharField(max_length=100, null=True, blank=True)
    notes = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        ordering = ['day_order']

    def __str__(self):
        return f"{self.workout_plan.title} - Day {self.day_order}"

class WorkoutExercise(models.Model):
    workout_day = models.ForeignKey(WorkoutDay, on_delete=models.CASCADE, related_name='exercises')
    exercise = models.ForeignKey(Exercise, on_delete=models.CASCADE, related_name='workout_exercises')
    order_index = models.IntegerField()
    set_count = models.IntegerField(null=True, blank=True)
    rep_count = models.IntegerField(null=True, blank=True)
    rep_range = models.CharField(max_length=50, null=True, blank=True)
    rir = models.IntegerField(null=True, blank=True)
    rpe = models.IntegerField(null=True, blank=True)
    rm_reference = models.CharField(max_length=50, null=True, blank=True)
    load_percentage = models.IntegerField(null=True, blank=True)
    recovery_seconds = models.IntegerField(null=True, blank=True)
    tempo = models.CharField(max_length=50, null=True, blank=True)
    execution_type = models.CharField(max_length=100, null=True, blank=True)
    technique_notes = models.TextField(null=True, blank=True)
    superset_group_id = models.IntegerField(null=True, blank=True)
    alternative_exercise = models.ForeignKey(
        Exercise, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='used_as_alternative',
    )
    load_value = models.DecimalField(max_digits=6, decimal_places=2, null=True, blank=True)
    LOAD_UNIT_KG = 'KG'
    LOAD_UNIT_PERCENT = 'PERCENT_1RM'
    LOAD_UNIT_BODYWEIGHT = 'BODYWEIGHT'
    LOAD_UNIT_CHOICES = [
        (LOAD_UNIT_KG, 'kg'),
        (LOAD_UNIT_PERCENT, '% 1RM'),
        (LOAD_UNIT_BODYWEIGHT, 'corpo libero'),
    ]
    load_unit = models.CharField(max_length=20, choices=LOAD_UNIT_CHOICES, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['order_index']

    def __str__(self):
        return f"{self.exercise.name} for {self.workout_day}"

class WorkoutAssignment(models.Model):
    workout_plan = models.ForeignKey(WorkoutPlan, on_delete=models.CASCADE, related_name='assignments')
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='workout_assignments')
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='workout_assignments_given')
    status = models.CharField(max_length=50) # ACTIVE, COMPLETED
    start_date = models.DateField(null=True, blank=True)
    end_date = models.DateField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    def __str__(self):
        return f"Plan {self.workout_plan.title} for {self.client}"

class WorkoutLog(models.Model):
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='workout_logs')
    workout_assignment = models.ForeignKey(WorkoutAssignment, on_delete=models.CASCADE, related_name='logs')
    workout_day = models.ForeignKey(WorkoutDay, on_delete=models.CASCADE, related_name='logs')
    workout_date = models.DateField()
    completion_status = models.CharField(max_length=50)
    perceived_difficulty = models.IntegerField(null=True, blank=True)
    total_duration_minutes = models.IntegerField(null=True, blank=True)
    client_notes = models.TextField(null=True, blank=True)
    coach_notes = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Log by {self.client} on {self.workout_date}"


class WorkoutSession(models.Model):
    assignment = models.ForeignKey(WorkoutAssignment, on_delete=models.CASCADE, related_name='sessions')
    workout_day = models.ForeignKey(WorkoutDay, on_delete=models.CASCADE, related_name='sessions')
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='workout_sessions')
    started_at = models.DateTimeField(default=timezone.now)
    ended_at = models.DateTimeField(null=True, blank=True)
    duration_minutes = models.IntegerField(null=True, blank=True)
    avg_rpe = models.FloatField(null=True, blank=True)
    notes = models.TextField(null=True, blank=True)
    completed = models.BooleanField(default=False)
    interrupted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-started_at']

    def __str__(self):
        return f"Session {self.id} - {self.client} on {self.started_at}"

    def recompute_summary(self):
        sets = self.set_logs.filter(completed=True)
        if self.ended_at and self.started_at:
            self.duration_minutes = int((self.ended_at - self.started_at).total_seconds() / 60)
        rpes = [s.rpe for s in sets if s.rpe is not None]
        self.avg_rpe = round(sum(rpes) / len(rpes), 1) if rpes else None


class WorkoutSetLog(models.Model):
    session = models.ForeignKey(WorkoutSession, on_delete=models.CASCADE, related_name='set_logs')
    workout_exercise = models.ForeignKey(WorkoutExercise, on_delete=models.CASCADE, related_name='set_logs')
    set_number = models.IntegerField()
    reps_done = models.IntegerField(null=True, blank=True)
    load_used = models.DecimalField(max_digits=6, decimal_places=2, null=True, blank=True)
    load_unit = models.CharField(max_length=20, null=True, blank=True)
    rpe = models.IntegerField(null=True, blank=True)
    notes = models.TextField(null=True, blank=True)
    completed = models.BooleanField(default=False)
    is_extra_set = models.BooleanField(default=False)
    exercise_substituted = models.BooleanField(default=False)
    actual_exercise = models.ForeignKey(
        Exercise, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='actual_in_set_logs',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['workout_exercise__order_index', 'set_number']
        unique_together = [('session', 'workout_exercise', 'set_number')]


def session_media_path(instance, filename):
    return f"sessions/{instance.session.id}/{filename}"


class SessionMedia(models.Model):
    TYPE_PHOTO = 'PHOTO'
    TYPE_VIDEO = 'VIDEO'
    TYPE_CHOICES = [(TYPE_PHOTO, 'Foto'), (TYPE_VIDEO, 'Video')]

    session = models.ForeignKey(WorkoutSession, on_delete=models.CASCADE, related_name='media')
    media_type = models.CharField(max_length=10, choices=TYPE_CHOICES)
    file = models.FileField(upload_to=session_media_path)
    coach_comment = models.TextField(null=True, blank=True)
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-uploaded_at']


class SessionCoachNote(models.Model):
    session = models.ForeignKey(WorkoutSession, on_delete=models.CASCADE, related_name='coach_notes')
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='session_notes')
    text = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']