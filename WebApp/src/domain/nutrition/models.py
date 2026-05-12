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


class NutritionPlan(models.Model):
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='nutrition_plans')
    title = models.CharField(max_length=200)
    description = models.TextField(null=True, blank=True)
    plan_type = models.CharField(max_length=100, null=True, blank=True)
    nutrition_goal = models.CharField(max_length=200, null=True, blank=True)
    daily_kcal = models.IntegerField(null=True, blank=True)
    protein_target_g = models.IntegerField(null=True, blank=True)
    carb_target_g = models.IntegerField(null=True, blank=True)
    fat_target_g = models.IntegerField(null=True, blank=True)
    meals_per_day = models.IntegerField(null=True, blank=True)
    status = models.CharField(max_length=50) # Es: DRAFT, PUBLISHED
    is_template = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.title} (by {self.coach})"


class Meal(models.Model):
    plan = models.ForeignKey(NutritionPlan, on_delete=models.CASCADE, related_name='meals')
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
    food = models.ForeignKey(Food, on_delete=models.CASCADE)
    quantity_g = models.FloatField()
    notes = models.TextField(null=True, blank=True)

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

    @property
    def fiber(self):
        return round(self.food.fibra_g * self.quantity_g / 100, 1)

    def __str__(self):
        return f"{self.quantity_g}g {self.food.nome_alimento}"


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

    def __str__(self):
        return f"Plan {self.nutrition_plan.title} for {self.client}"
