/* Athlynk · Nutrition Wizard · WEEKLY builder mixin
   Day tabs, aggregates over filled days, duplicate-day logic.
   Relies on DAILY mixin for per-meal kcal/macro helpers. */

function nutritionWizardWeeklyMixin() {
  return {
    weekDayLabel(code) {
      const d = this.weekDays.find(x => x.code === code);
      return d ? d.label : code;
    },
    dayMealCount(code) {
      return this.meals.filter(m => m.day_of_week === code).length;
    },
    dayKcal(code) {
      return Math.round(this.meals
        .filter(m => m.day_of_week === code)
        .reduce((s, m) => s + this.mealKcal(m), 0));
    },
    dayMacro(code, key) {
      return Math.round(this.meals
        .filter(m => m.day_of_week === code)
        .reduce((s, m) => s + this.mealMacro(m, key), 0));
    },
    hasAnyDay() {
      return this.weekDays.some(d => this.dayMealCount(d.code) > 0);
    },
    hasOtherDayWithMeals() {
      return this.weekDays.some(d => d.code !== this.activeDay && this.dayMealCount(d.code) > 0);
    },
    filledDaysCount() {
      return this.weekDays.filter(d => this.dayMealCount(d.code) > 0).length;
    },
    avgKcal() {
      const filled = this.weekDays.filter(d => this.dayMealCount(d.code) > 0);
      if (filled.length === 0) return 0;
      const tot = filled.reduce((s, d) => s + this.dayKcal(d.code), 0);
      return Math.round(tot / filled.length);
    },
    avgMacro(key) {
      const filled = this.weekDays.filter(d => this.dayMealCount(d.code) > 0);
      if (filled.length === 0) return 0;
      const tot = filled.reduce((s, d) => s + this.dayMacro(d.code, key), 0);
      return Math.round(tot / filled.length);
    },
    duplicateFromDay(srcCode) {
      const dest = this.activeDay;
      const destCount = this.dayMealCount(dest);
      let mode = 'append';
      if (destCount > 0) {
        const ans = confirm('Il giorno ' + this.weekDayLabel(dest) + ' contiene gia ' + destCount +
          ' pasti.\n\nOK = Sostituisci, Annulla = Aggiungi');
        mode = ans ? 'replace' : 'append';
      }
      if (mode === 'replace') {
        this.meals = this.meals.filter(m => m.day_of_week !== dest);
      }
      const src = this.meals.filter(m => m.day_of_week === srcCode);
      src.forEach((m, i) => {
        this.meals.push({
          _key: 'm' + Date.now() + '_' + i + Math.random().toString(36).slice(2, 4),
          name: m.name,
          time_of_day: m.time_of_day,
          notes: m.notes,
          day_of_week: dest,
          items: m.items.map(it => ({ ...it })),
        });
      });
    },
  };
}

window.nutritionWizardWeeklyMixin = nutritionWizardWeeklyMixin;
