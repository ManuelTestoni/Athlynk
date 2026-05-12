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


# ---------------------------------------------------------------------------
# Progression engine models
# ---------------------------------------------------------------------------

class WeekDefinition(models.Model):
    TYPE_STANDARD = 'STANDARD'
    TYPE_DELOAD = 'DELOAD'
    TYPE_TEST = 'TEST'
    TYPE_TECHNIQUE = 'TECHNIQUE'
    TYPE_RECOVERY = 'RECOVERY'
    WEEK_TYPE_CHOICES = [
        (TYPE_STANDARD, 'Standard'),
        (TYPE_DELOAD, 'Deload'),
        (TYPE_TEST, 'Test'),
        (TYPE_TECHNIQUE, 'Tecnica'),
        (TYPE_RECOVERY, 'Recovery'),
    ]

    workout_plan = models.ForeignKey(WorkoutPlan, on_delete=models.CASCADE, related_name='weeks')
    week_number = models.PositiveIntegerField()
    label = models.CharField(max_length=40, blank=True, default='')
    week_type = models.CharField(max_length=20, choices=WEEK_TYPE_CHOICES, default=TYPE_STANDARD)
    preset = models.CharField(max_length=40, blank=True, default='')
    notes = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = [('workout_plan', 'week_number')]
        ordering = ['week_number']

    def __str__(self):
        return f"{self.workout_plan_id} S{self.week_number} ({self.week_type})"


class ProgressionRule(models.Model):
    FAMILY_LOAD = 'LOAD'
    FAMILY_VOLUME = 'VOLUME'
    FAMILY_INTENSITY = 'INTENSITY'
    FAMILY_DENSITY = 'DENSITY'
    FAMILY_TEMPO = 'TEMPO'
    FAMILY_ROM = 'ROM'
    FAMILY_VARIANT = 'VARIANT'
    FAMILY_FREQUENCY = 'FREQUENCY'
    FAMILY_UNDULATION = 'UNDULATION'
    FAMILY_DELOAD = 'DELOAD'
    FAMILY_VELOCITY = 'VELOCITY'
    FAMILY_CHOICES = [
        (FAMILY_LOAD, 'Carico'),
        (FAMILY_VOLUME, 'Volume'),
        (FAMILY_INTENSITY, 'Intensità'),
        (FAMILY_DENSITY, 'Densità'),
        (FAMILY_TEMPO, 'Tempo'),
        (FAMILY_ROM, 'ROM'),
        (FAMILY_VARIANT, 'Variante'),
        (FAMILY_FREQUENCY, 'Frequenza'),
        (FAMILY_UNDULATION, 'Ondulazione'),
        (FAMILY_DELOAD, 'Deload'),
        (FAMILY_VELOCITY, 'Velocità'),
    ]

    SUBTYPE_CHOICES = [
        # LOAD
        ('LOAD_LINEAR', 'Carico lineare'),
        ('LOAD_PERCENT', 'Carico percentuale'),
        ('LOAD_MICRO', 'Micro-load'),
        ('LOAD_MANUAL', 'Carico manuale per settimana'),
        ('LOAD_TOP_BACKOFF', 'Top set / Back-off'),
        # VOLUME
        ('VOL_SETS', 'Progressione serie'),
        ('VOL_REPS', 'Progressione reps'),
        ('VOL_SETS_REPS', 'Serie + reps combinate'),
        ('VOL_DOUBLE', 'Double progression'),
        ('VOL_TRIPLE', 'Triple progression'),
        # INTENSITY
        ('INT_RPE', 'RPE progressivo'),
        ('INT_RIR', 'RIR progressivo'),
        ('INT_PCT1RM', '% 1RM per settimana'),
        # DENSITY
        ('DEN_REST', 'Riduzione recupero'),
        ('DEN_TIME', 'Densità tempo'),
        # TEMPO
        ('TEMPO_PRESET', 'Preset tempo'),
        ('TEMPO_ECC', 'Tempo eccentrico'),
        ('TEMPO_CON', 'Tempo concentrico'),
        ('TEMPO_PAUSE', 'Pausa isometrica'),
        # ROM
        ('ROM_INCREASE', 'Aumento ROM'),
        ('ROM_DEFICIT', 'Deficit / rialzo'),
        ('ROM_PAUSE', 'Pausa in allungamento'),
        # VARIANT
        ('VAR_TRANSITION', 'Transizione variante'),
        # FREQUENCY
        ('FREQ_ADD', 'Aumento frequenza'),
        # UNDULATION
        ('UND_WUP', 'WUP — Ondulata settimanale'),
        ('UND_DUP', 'DUP — Ondulata giornaliera'),
        ('UND_BLOCK', 'Periodizzazione a blocchi'),
        # DELOAD
        ('DEL_AUTO', 'Deload automatico'),
        ('DEL_MANUAL', 'Deload manuale'),
        # VELOCITY
        ('VEL_TARGET', 'Target velocità'),
        ('VEL_RANGE', 'Range velocità'),
    ]

    METRIC_LOAD = 'load'
    METRIC_SETS = 'sets'
    METRIC_REPS = 'reps'
    METRIC_REP_RANGE = 'rep_range'
    METRIC_RPE = 'rpe'
    METRIC_RIR = 'rir'
    METRIC_REST = 'rest'
    METRIC_TEMPO = 'tempo'
    METRIC_ROM = 'rom'
    METRIC_DURATION = 'duration'
    METRIC_VARIANT = 'exercise_variant'
    METRIC_FREQUENCY = 'frequency'
    METRIC_VELOCITY = 'velocity'
    METRIC_NOTES = 'notes'
    METRIC_CHOICES = [
        (METRIC_LOAD, 'Carico'),
        (METRIC_SETS, 'Serie'),
        (METRIC_REPS, 'Ripetizioni'),
        (METRIC_REP_RANGE, 'Range ripetizioni'),
        (METRIC_RPE, 'RPE'),
        (METRIC_RIR, 'RIR'),
        (METRIC_REST, 'Recupero'),
        (METRIC_TEMPO, 'Tempo'),
        (METRIC_ROM, 'ROM'),
        (METRIC_DURATION, 'Durata'),
        (METRIC_VARIANT, 'Variante'),
        (METRIC_FREQUENCY, 'Frequenza'),
        (METRIC_VELOCITY, 'Velocità'),
        (METRIC_NOTES, 'Note'),
    ]

    MODE_FIXED = 'FIXED_INCREMENT'
    MODE_PERCENT = 'PERCENT_INCREMENT'
    MODE_EXPLICIT = 'EXPLICIT_VALUES'
    MODE_RULE = 'RULE_BASED'
    MODE_MILESTONE = 'MILESTONE_BASED'
    MODE_OVERRIDE = 'MANUAL_OVERRIDE'
    MODE_CHOICES = [
        (MODE_FIXED, 'Incremento fisso'),
        (MODE_PERCENT, 'Incremento percentuale'),
        (MODE_EXPLICIT, 'Valori espliciti'),
        (MODE_RULE, 'Basato su regola'),
        (MODE_MILESTONE, 'Basato su milestone'),
        (MODE_OVERRIDE, 'Override manuale'),
    ]

    CONFLICT_LAST_WINS = 'LAST_WINS'
    CONFLICT_ADD = 'ADD'
    CONFLICT_MULTIPLY = 'MULTIPLY'
    CONFLICT_REPLACE = 'REPLACE'
    CONFLICT_ERROR = 'ERROR'
    CONFLICT_CHOICES = [
        (CONFLICT_LAST_WINS, 'Ultimo prevale'),
        (CONFLICT_ADD, 'Somma'),
        (CONFLICT_MULTIPLY, 'Moltiplica'),
        (CONFLICT_REPLACE, 'Sostituisce'),
        (CONFLICT_ERROR, 'Errore'),
    ]

    workout_plan = models.ForeignKey(WorkoutPlan, on_delete=models.CASCADE, related_name='progression_rules')
    workout_exercise = models.ForeignKey(WorkoutExercise, on_delete=models.CASCADE, related_name='progression_rules')
    order_index = models.PositiveIntegerField(default=0)

    family = models.CharField(max_length=20, choices=FAMILY_CHOICES)
    subtype = models.CharField(max_length=40, choices=SUBTYPE_CHOICES)
    target_metric = models.CharField(max_length=30, choices=METRIC_CHOICES)
    application_mode = models.CharField(max_length=30, choices=MODE_CHOICES, default=MODE_FIXED)

    start_week = models.PositiveIntegerField(default=1)
    end_week = models.PositiveIntegerField(null=True, blank=True)

    parameters = models.JSONField(default=dict, blank=True)
    stackable = models.BooleanField(default=True)
    conflict_strategy = models.CharField(max_length=20, choices=CONFLICT_CHOICES, default=CONFLICT_LAST_WINS)
    label = models.CharField(max_length=80, blank=True, default='')

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['workout_exercise_id', 'order_index', 'id']

    def __str__(self):
        return f"{self.subtype} on ex{self.workout_exercise_id}"


class WeeklyOverride(models.Model):
    workout_exercise = models.ForeignKey(WorkoutExercise, on_delete=models.CASCADE, related_name='weekly_overrides')
    week_number = models.PositiveIntegerField()
    metric = models.CharField(max_length=30, choices=ProgressionRule.METRIC_CHOICES)
    value_json = models.JSONField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = [('workout_exercise', 'week_number', 'metric')]
        ordering = ['workout_exercise_id', 'week_number', 'metric']

    def __str__(self):
        return f"override ex{self.workout_exercise_id} S{self.week_number} {self.metric}"


class WeeklyValue(models.Model):
    workout_exercise = models.ForeignKey(WorkoutExercise, on_delete=models.CASCADE, related_name='weekly_values')
    week_number = models.PositiveIntegerField()

    load_value = models.DecimalField(max_digits=6, decimal_places=2, null=True, blank=True)
    load_unit = models.CharField(max_length=20, blank=True, default='')
    set_count = models.PositiveSmallIntegerField(null=True, blank=True)
    rep_range = models.CharField(max_length=32, blank=True, default='')
    rpe = models.DecimalField(max_digits=3, decimal_places=1, null=True, blank=True)
    rir = models.PositiveSmallIntegerField(null=True, blank=True)
    recovery_seconds = models.PositiveIntegerField(null=True, blank=True)
    tempo = models.CharField(max_length=10, blank=True, default='')
    rom_stage = models.CharField(max_length=20, blank=True, default='')
    variant_exercise = models.ForeignKey(
        Exercise, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='weekly_value_variants',
    )
    velocity_target = models.DecimalField(max_digits=4, decimal_places=2, null=True, blank=True)
    notes = models.TextField(blank=True, default='')

    is_override = models.BooleanField(default=False)
    is_deload = models.BooleanField(default=False)
    computed_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = [('workout_exercise', 'week_number')]
        ordering = ['workout_exercise_id', 'week_number']
        indexes = [models.Index(fields=['workout_exercise', 'week_number'])]

    def __str__(self):
        return f"value ex{self.workout_exercise_id} S{self.week_number}"


class ExerciseVariantTransition(models.Model):
    workout_exercise = models.ForeignKey(WorkoutExercise, on_delete=models.CASCADE, related_name='variant_transitions')
    week_number = models.PositiveIntegerField()
    target_exercise = models.ForeignKey(Exercise, on_delete=models.CASCADE, related_name='variant_transition_targets')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = [('workout_exercise', 'week_number')]
        ordering = ['workout_exercise_id', 'week_number']