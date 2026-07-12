from django.db import models


class Food(models.Model):
    nome_alimento = models.CharField(max_length=200, db_column='Nome_Alimento')
    categoria_alimento = models.CharField(max_length=100, null=True, blank=True, db_column='Categoria_Alimento')
    energia_kcal = models.FloatField(default=0, db_column='Energia(Kcal)')
    proteine_g = models.FloatField(default=0, db_column='Proteine(g)')
    lipidi_g = models.FloatField(default=0, db_column='Lipidi(g)')
    colesterolo_mg = models.FloatField(default=0, db_column='Colesterolo(mg)')
    carboidrati_g = models.FloatField(default=0, db_column='Carboidrati(g)')
    carboidrati_solubili_g = models.FloatField(default=0, db_column='Carboidrati_Solubili(g)')
    fibra_g = models.FloatField(default=0, db_column='Fibra(g)')
    fe_mg = models.FloatField(default=0, db_column='Fe(mg)')
    ca_mg = models.FloatField(default=0, db_column='Ca(mg)')
    na_mg = models.FloatField(default=0, db_column='Na(mg)')
    k_mg = models.FloatField(default=0, db_column='K(mg)')
    p_mg = models.FloatField(default=0, db_column='P(mg)')
    zn_mg = models.FloatField(default=0, db_column='Zn(mg)')
    mg_mg = models.FloatField(default=0, db_column='Mg(mg)')
    cu_mg = models.FloatField(default=0, db_column='Cu(mg)')
    se_ug = models.FloatField(default=0, db_column='Se(ug)')
    i_ug = models.FloatField(default=0, db_column='I(ug)')
    mn_mg = models.FloatField(default=0, db_column='Mn(mg)')
    vit_b1_mg = models.FloatField(default=0, db_column='Vit_B1(mg)')
    vit_b2_mg = models.FloatField(default=0, db_column='Vit_B2(mg)')
    vit_c_mg = models.FloatField(default=0, db_column='Vit_C(mg)')
    niacina_mg = models.FloatField(default=0, db_column='Niacina(mg)')
    vit_b6_mg = models.FloatField(default=0, db_column='Vit_B6(mg)')
    folati_ug = models.FloatField(default=0, db_column='Folati(ug)')
    vit_b12_ug = models.FloatField(default=0, db_column='Vit_B12(ug)')
    lipidi_saturi_g = models.FloatField(default=0, db_column='Lipidi_Saturi(g)')
    isoleucina_mg = models.FloatField(default=0, db_column='Isoleucina(mg)')
    leucina_mg = models.FloatField(default=0, db_column='Leucina(mg)')
    valina_mg = models.FloatField(default=0, db_column='Valina(mg)')
    lattosio_g = models.FloatField(default=0, db_column='Lattosio(g)')
    genericity_score = models.FloatField(default=0.0, db_index=True, db_column='Genericity_Score')

    class Meta:
        ordering = ['-genericity_score', 'nome_alimento']

    def __str__(self):
        return self.nome_alimento


class NutritionFolder(models.Model):
    coach = models.ForeignKey(
        'accounts.CoachProfile', on_delete=models.CASCADE,
        related_name='nutrition_folders',
    )
    title = models.CharField(max_length=120)
    label_text = models.CharField(max_length=40, blank=True, default='')
    label_color = models.CharField(max_length=20, blank=True, default='')
    order = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['order', 'title']
        unique_together = [('coach', 'title')]

    def __str__(self):
        return f"{self.title} ({self.coach_id})"


class NutritionPlan(models.Model):
    PLAN_KIND_CHOICES = [
        ('DAILY', 'Giornaliero'),
        ('WEEKLY', 'Settimanale'),
    ]
    # FOOD  → coach builds meals/foods (classic diet).
    # MACRO → coach only sets macro targets; the client logs the foods they eat.
    PLAN_MODE_CHOICES = [
        ('FOOD', 'Alimenti'),
        ('MACRO', 'Macronutrienti'),
    ]

    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='nutrition_plans')
    title = models.CharField(max_length=200)
    description = models.TextField(null=True, blank=True)
    plan_type = models.CharField(max_length=100, null=True, blank=True)
    plan_kind = models.CharField(max_length=10, choices=PLAN_KIND_CHOICES, default='DAILY')
    plan_mode = models.CharField(max_length=10, choices=PLAN_MODE_CHOICES, default='FOOD')
    nutrition_goal = models.CharField(max_length=200, null=True, blank=True)
    daily_kcal = models.IntegerField(null=True, blank=True)
    protein_target_g = models.IntegerField(null=True, blank=True)
    carb_target_g = models.IntegerField(null=True, blank=True)
    fat_target_g = models.IntegerField(null=True, blank=True)
    meals_per_day = models.IntegerField(null=True, blank=True)
    status = models.CharField(max_length=50) # Es: DRAFT, PUBLISHED
    is_template = models.BooleanField(default=False)
    include_substitutions_in_avg = models.BooleanField(default=False)
    folder = models.ForeignKey(
        NutritionFolder, null=True, blank=True,
        on_delete=models.SET_NULL, related_name='plans',
    )
    supplement_sheet = models.OneToOneField(
        'SupplementProtocol', null=True, blank=True,
        on_delete=models.SET_NULL, related_name='nutrition_plan',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=['coach', 'status']),
            models.Index(fields=['coach', 'is_template']),
        ]

    def __str__(self):
        return f"{self.title} (by {self.coach})"


class DietDay(models.Model):
    DAY_CHOICES = [
        ('MONDAY', 'Lunedì'),
        ('TUESDAY', 'Martedì'),
        ('WEDNESDAY', 'Mercoledì'),
        ('THURSDAY', 'Giovedì'),
        ('FRIDAY', 'Venerdì'),
        ('SATURDAY', 'Sabato'),
        ('SUNDAY', 'Domenica'),
    ]
    plan = models.ForeignKey(NutritionPlan, on_delete=models.CASCADE, related_name='days')
    day_of_week = models.CharField(max_length=10, choices=DAY_CHOICES)
    order = models.PositiveIntegerField(default=0)
    notes = models.TextField(null=True, blank=True)
    # Per-day macro targets — used only by WEEKLY plans in MACRO mode.
    target_kcal = models.PositiveIntegerField(null=True, blank=True)
    target_protein_g = models.PositiveIntegerField(null=True, blank=True)
    target_carb_g = models.PositiveIntegerField(null=True, blank=True)
    target_fat_g = models.PositiveIntegerField(null=True, blank=True)

    class Meta:
        ordering = ['order']
        unique_together = [('plan', 'day_of_week')]

    def __str__(self):
        return f"{self.get_day_of_week_display()} – {self.plan.title}"


class Meal(models.Model):
    plan = models.ForeignKey(NutritionPlan, on_delete=models.CASCADE, related_name='meals')
    day = models.ForeignKey(DietDay, on_delete=models.CASCADE, related_name='meals', null=True, blank=True)
    name = models.CharField(max_length=100)
    order = models.PositiveIntegerField(default=0)
    time_of_day = models.CharField(max_length=10, null=True, blank=True)
    notes = models.TextField(null=True, blank=True)

    class Meta:
        ordering = ['order']

    def __str__(self):
        return f"{self.name} – {self.plan.title}"


class MealItem(models.Model):
    meal = models.ForeignKey(Meal, on_delete=models.CASCADE, related_name='items')
    food = models.ForeignKey(Food, on_delete=models.CASCADE, null=True, blank=True)
    quantity_g = models.FloatField()
    notes = models.TextField(null=True, blank=True)
    uncertain = models.BooleanField(default=False)
    raw_name = models.CharField(max_length=200, null=True, blank=True)

    @property
    def kcal(self):
        if not self.food:
            return 0
        return round(self.food.energia_kcal * self.quantity_g / 100, 1)

    @property
    def protein(self):
        if not self.food:
            return 0
        return round(self.food.proteine_g * self.quantity_g / 100, 1)

    @property
    def carbs(self):
        if not self.food:
            return 0
        return round(self.food.carboidrati_g * self.quantity_g / 100, 1)

    @property
    def fat(self):
        if not self.food:
            return 0
        return round(self.food.lipidi_g * self.quantity_g / 100, 1)

    @property
    def fiber(self):
        if not self.food:
            return 0
        return round(self.food.fibra_g * self.quantity_g / 100, 1)

    def __str__(self):
        label = self.food.nome_alimento if self.food else (self.raw_name or '???')
        return f"{self.quantity_g}g {label}"


class MealItemSubstitution(models.Model):
    MODE_CHOICES = [
        ('ISOKCAL', 'Isocalorica'),
        ('ISOPROT', 'Isoproteica'),
        ('ISOCARB', 'Isoglucidica'),
    ]
    item = models.ForeignKey(MealItem, on_delete=models.CASCADE, related_name='substitutions')
    food = models.ForeignKey(Food, on_delete=models.CASCADE)
    mode = models.CharField(max_length=10, choices=MODE_CHOICES)
    quantity_g = models.FloatField()
    order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ['order', 'id']

    @property
    def kcal(self):
        return round(self.food.energia_kcal * self.quantity_g / 100, 1)

    @property
    def protein(self):
        return round(self.food.proteine_g * self.quantity_g / 100, 1)

    @property
    def carbs(self):
        return round(self.food.carboidrati_g * self.quantity_g / 100, 1)

    @property
    def fat(self):
        return round(self.food.lipidi_g * self.quantity_g / 100, 1)

    def __str__(self):
        return f"[{self.mode}] {self.quantity_g}g {self.food.nome_alimento}"


# Free-text supplements: the coach types the name and quantity, picks a unit and
# a timing. No catalog. A protocol doubles as a standalone "scheda" (assignable to
# athletes) and as the per-diet supplement section (NutritionPlan.supplement_sheet).
SUPPLEMENT_UNIT_CHOICES = [('mg', 'mg'), ('g', 'g'), ('cps', 'cps')]


class SupplementProtocol(models.Model):
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='supplement_protocols')
    title = models.CharField(max_length=200)
    notes = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-updated_at']

    def __str__(self):
        return f"{self.title} (by {self.coach_id})"


class SupplementItem(models.Model):
    protocol = models.ForeignKey(SupplementProtocol, on_delete=models.CASCADE, related_name='items')
    name = models.CharField(max_length=200)
    quantity = models.CharField(max_length=50, blank=True, default='')
    unit = models.CharField(max_length=10, choices=SUPPLEMENT_UNIT_CHOICES, blank=True, default='g')
    timing = models.CharField(max_length=120, blank=True, default='')
    notes = models.TextField(blank=True, default='')
    order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ['order', 'id']

    def __str__(self):
        return f"{self.quantity}{self.unit} {self.name}".strip()


class SupplementProtocolAssignment(models.Model):
    protocol = models.ForeignKey(SupplementProtocol, on_delete=models.CASCADE, related_name='assignments')
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='supplement_assignments')
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='supplement_assignments_given')
    status = models.CharField(max_length=20, default='ACTIVE')
    assigned_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=['coach', 'status']),
        ]

    def __str__(self):
        return f"{self.protocol.title} → {self.client_id}"


class NutritionAssignment(models.Model):
    DURATION_UNIT_WEEKS = 'WEEKS'
    DURATION_UNIT_MONTHS = 'MONTHS'
    DURATION_UNIT_CHOICES = [(DURATION_UNIT_WEEKS, 'settimane'), (DURATION_UNIT_MONTHS, 'mesi')]

    nutrition_plan = models.ForeignKey(NutritionPlan, on_delete=models.CASCADE, related_name='assignments')
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='nutrition_assignments')
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='nutrition_assignments_given')
    assigned_at = models.DateTimeField(auto_now_add=True)
    start_date = models.DateField(null=True, blank=True)
    end_date = models.DateField(null=True, blank=True)
    # The coach-chosen duration that produced end_date, kept for display/audit
    # (start_date/end_date remain authoritative for scheduling logic).
    duration_value = models.PositiveSmallIntegerField(null=True, blank=True)
    duration_unit = models.CharField(max_length=10, choices=DURATION_UNIT_CHOICES, null=True, blank=True)
    status = models.CharField(max_length=50) # Es: ACTIVE, COMPLETED, CANCELLED
    notes = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=['client', 'coach', 'status']),
            models.Index(fields=['coach', '-assigned_at']),
        ]

    def __str__(self):
        return f"Plan {self.nutrition_plan.title} for {self.client}"


class ClientMacroLogEntry(models.Model):
    """A food the client logged against a MACRO-mode plan assignment.

    The coach sets only macro targets; the client records what they actually
    eat. Macros are derived live from the linked Food row + quantity, exactly
    like MealItem, so totals stay consistent across the app.
    """
    DAY_CHOICES = DietDay.DAY_CHOICES

    assignment = models.ForeignKey(
        NutritionAssignment, on_delete=models.CASCADE, related_name='macro_log',
    )
    # Null for DAILY plans; the weekday code (MONDAY…) for WEEKLY plans.
    day_of_week = models.CharField(max_length=10, choices=DAY_CHOICES, null=True, blank=True)
    # Calendar date this entry was logged for. Entries are locked after midnight.
    log_date = models.DateField(null=True, blank=True, db_index=True)
    # Meal group name (e.g. "Colazione", "Pranzo"). Null for legacy entries.
    meal_name = models.CharField(max_length=100, null=True, blank=True)
    food = models.ForeignKey(Food, on_delete=models.CASCADE, null=True, blank=True)
    raw_name = models.CharField(max_length=200, null=True, blank=True)
    quantity_g = models.FloatField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['created_at', 'id']
        indexes = [
            models.Index(fields=['assignment', 'day_of_week']),
            models.Index(fields=['assignment', 'log_date'], name='nutrition_c_assign_logdate_idx'),
        ]

    @property
    def kcal(self):
        if not self.food:
            return 0
        return round(self.food.energia_kcal * self.quantity_g / 100, 1)

    @property
    def protein(self):
        if not self.food:
            return 0
        return round(self.food.proteine_g * self.quantity_g / 100, 1)

    @property
    def carbs(self):
        if not self.food:
            return 0
        return round(self.food.carboidrati_g * self.quantity_g / 100, 1)

    @property
    def fat(self):
        if not self.food:
            return 0
        return round(self.food.lipidi_g * self.quantity_g / 100, 1)

    def __str__(self):
        label = self.food.nome_alimento if self.food else (self.raw_name or '???')
        return f"{self.quantity_g}g {label} (log {self.assignment_id})"
