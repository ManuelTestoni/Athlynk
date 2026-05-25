/* Athlynk · Nutrition Wizard · DAILY builder mixin
   Pure helpers for single-day plans. Methods assume Alpine `this` binding
   provided by nutritionWizard(). Merged into the wizard via Object.assign. */

function nutritionWizardDailyMixin() {
  const _primary = (it, key) => {
    const q = parseFloat(it.quantity_g) || 0;
    return (it[key + '_per_100g'] || 0) * q / 100;
  };
  const _sub = (s, key) => {
    const q = parseFloat(s.quantity_g) || 0;
    return (s[key + '_per_100g'] || 0) * q / 100;
  };
  return {
    /* Effective contribution of one item — averages with substitutions when the
       plan toggle is on AND the item has at least one substitution.            */
    itemEffective(item, key) {
      const primary = _primary(item, key);
      const subs = item.substitutions || [];
      if (!this.include_substitutions_in_avg || subs.length === 0) return primary;
      const total = primary + subs.reduce((s, x) => s + _sub(x, key), 0);
      return total / (1 + subs.length);
    },
    mealKcal(meal) {
      return Math.round(meal.items.reduce((s, i) => s + this.itemEffective(i, 'kcal'), 0));
    },
    mealMacro(meal, key) {
      return Math.round(meal.items.reduce((s, i) => s + this.itemEffective(i, key), 0));
    },
    totalKcal() {
      return Math.round(this.meals.reduce((s, m) => s + this.mealKcal(m), 0));
    },
    totalMacro(key) {
      return Math.round(this.meals.reduce((s, m) => s + this.mealMacro(m, key), 0));
    },
    itemMacros(item) {
      const k = Math.round(this.itemEffective(item, 'kcal'));
      const p = this.itemEffective(item, 'protein').toFixed(1);
      const c = this.itemEffective(item, 'carb').toFixed(1);
      const f = this.itemEffective(item, 'fat').toFixed(1);
      const avg = (this.include_substitutions_in_avg && (item.substitutions || []).length > 0)
        ? ' · media' : '';
      return k + ' kcal · P ' + p + ' · C ' + c + ' · F ' + f + avg;
    },
    hasAnyMealWithItem() {
      return this.meals.some(m => m.items.length > 0);
    },
  };
}

window.nutritionWizardDailyMixin = nutritionWizardDailyMixin;
