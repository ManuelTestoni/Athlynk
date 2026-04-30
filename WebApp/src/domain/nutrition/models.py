from django.db import models


class Food(models.Model):
    name = models.CharField(max_length=200)
    category = models.CharField(max_length=100, null=True, blank=True)
    kcal_per_100g = models.FloatField(default=0)
    protein_per_100g = models.FloatField(default=0)
    carb_per_100g = models.FloatField(default=0)
    fat_per_100g = models.FloatField(default=0)
    fiber_per_100g = models.FloatField(default=0)
    sugar_per_100g = models.FloatField(default=0)

    class Meta:
        ordering = ['name']

    def __str__(self):
        return self.name


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
        return round(self.food.kcal_per_100g * self.quantity_g / 100, 1)

    @property
    def protein(self):
        return round(self.food.protein_per_100g * self.quantity_g / 100, 1)

    @property
    def carbs(self):
        return round(self.food.carb_per_100g * self.quantity_g / 100, 1)

    @property
    def fat(self):
        return round(self.food.fat_per_100g * self.quantity_g / 100, 1)

    @property
    def fiber(self):
        return round(self.food.fiber_per_100g * self.quantity_g / 100, 1)

    def __str__(self):
        return f"{self.quantity_g}g {self.food.name}"


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
