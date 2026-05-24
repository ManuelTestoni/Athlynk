/* Athlynk · Nutrition Wizard · DAILY builder mixin
   Pure helpers for single-day plans. Methods assume Alpine `this` binding
   provided by nutritionWizard(). Merged into the wizard via Object.assign. */

function nutritionWizardDailyMixin() {
  return {
    mealKcal(meal) {
      return Math.round(meal.items.reduce((s, i) =>
        s + (i.kcal_per_100g * (parseFloat(i.quantity_g) || 0) / 100), 0));
    },
    mealMacro(meal, key) {
      const field = key + '_per_100g';
      return Math.round(meal.items.reduce((s, i) =>
        s + (i[field] * (parseFloat(i.quantity_g) || 0) / 100), 0));
    },
    totalKcal() {
      return Math.round(this.meals.reduce((s, m) => s + this.mealKcal(m), 0));
    },
    totalMacro(key) {
      return Math.round(this.meals.reduce((s, m) => s + this.mealMacro(m, key), 0));
    },
    itemMacros(item) {
      const q = parseFloat(item.quantity_g) || 0;
      const k = Math.round(item.kcal_per_100g * q / 100);
      const p = (item.protein_per_100g * q / 100).toFixed(1);
      const c = (item.carb_per_100g * q / 100).toFixed(1);
      const f = (item.fat_per_100g * q / 100).toFixed(1);
      return k + ' kcal · P ' + p + ' · C ' + c + ' · F ' + f;
    },
    hasAnyMealWithItem() {
      return this.meals.some(m => m.items.length > 0);
    },
  };
}

window.nutritionWizardDailyMixin = nutritionWizardDailyMixin;
