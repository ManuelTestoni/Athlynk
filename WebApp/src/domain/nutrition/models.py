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

    class Meta:
        ordering = ['nome_alimento']

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

    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='nutrition_plans')
    title = models.CharField(max_length=200)
    description = models.TextField(null=True, blank=True)
    plan_type = models.CharField(max_length=100, null=True, blank=True)
    plan_kind = models.CharField(max_length=10, choices=PLAN_KIND_CHOICES, default='DAILY')
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
        'SupplementSheet', null=True, blank=True,
        on_delete=models.SET_NULL, related_name='nutrition_plan',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

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


class Supplement(models.Model):
    name = models.CharField(max_length=200)
    category = models.CharField(max_length=100, null=True, blank=True)
    description = models.TextField(null=True, blank=True)
    unit = models.CharField(max_length=20, default='g')

    class Meta:
        ordering = ['name']

    def __str__(self):
        return self.name


class SupplementSheet(models.Model):
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='supplement_sheets')
    title = models.CharField(max_length=200)
    notes = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.title} (by {self.coach})"


class SupplementSheetItem(models.Model):
    sheet = models.ForeignKey(SupplementSheet, on_delete=models.CASCADE, related_name='items')
    supplement = models.ForeignKey(Supplement, on_delete=models.CASCADE)
    dose = models.CharField(max_length=100)
    timing = models.CharField(max_length=100, null=True, blank=True)
    notes = models.TextField(null=True, blank=True)
    order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ['order']

    def __str__(self):
        return f"{self.dose} {self.supplement.name}"


class SupplementAssignment(models.Model):
    sheet = models.ForeignKey(SupplementSheet, on_delete=models.CASCADE, related_name='assignments')
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='supplement_assignments')
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='supplement_assignments_given')
    status = models.CharField(max_length=50, default='ACTIVE')
    notes = models.TextField(null=True, blank=True)
    assigned_at = models.DateTimeField(auto_now_add=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.sheet.title} → {self.client}"


class NutritionAssignment(models.Model):
    nutrition_plan = models.ForeignKey(NutritionPlan, on_delete=models.CASCADE, related_name='assignments')
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='nutrition_assignments')
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='nutrition_assignments_given')
    assigned_at = models.DateTimeField(auto_now_add=True)
    start_date = models.DateField(null=True, blank=True)
    end_date = models.DateField(null=True, blank=True)
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
