from django.db import models

class Exercise(models.Model):
    name = models.CharField(max_length=200)
    slug = models.SlugField(max_length=200, unique=True)
    description = models.TextField(null=True, blank=True)
    instructions = models.TextField(null=True, blank=True)
    target_muscles = models.CharField(max_length=255, null=True, blank=True)
    secondary_muscles = models.CharField(max_length=255, null=True, blank=True)
    equipment = models.CharField(max_length=200, null=True, blank=True)
    movement_pattern = models.CharField(max_length=100, null=True, blank=True)
    difficulty_level = models.CharField(max_length=50, null=True, blank=True)
    exercise_type = models.CharField(max_length=50, null=True, blank=True)
    alternative_exercises_notes = models.TextField(null=True, blank=True)
    video_url = models.URLField(max_length=500, null=True, blank=True)
    image_url = models.URLField(max_length=500, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.name

class WorkoutPlan(models.Model):
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='workout_plans')
    title = models.CharField(max_length=200)
    description = models.TextField(null=True, blank=True)
    level = models.CharField(max_length=50, null=True, blank=True)
    goal = models.CharField(max_length=200, null=True, blank=True)
    is_template = models.BooleanField(default=False)
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