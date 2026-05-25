/* Athlynk · Nutrition Wizard · main Alpine component
   Backs pages/nutrizione/piano_create.html. Init data comes from
   window.NUTRITION_WIZARD_INIT. DAILY + WEEKLY behaviour is split into
   nutrition_wizard_builder_daily.js / _weekly.js mixins. */

(function () {
  if (!window.nutCsrfToken) {
    window.nutCsrfToken = function () {
      return document.cookie.split('; ').find(r => r.startsWith('csrftoken='))?.split('=')[1]
        || (window.NUTRITION_WIZARD_INIT && window.NUTRITION_WIZARD_INIT.csrf)
        || '';
    };
  }
})();

function nutritionWizard() {
  const INIT = window.NUTRITION_WIZARD_INIT;
  const plan = INIT.plan;

  const seedMeals = (INIT.meals || []).map((m, i) => ({
    _key: 'm' + Date.now() + '_' + i,
    name: m.name,
    time_of_day: m.time_of_day || '',
    notes: m.notes || '',
    day_of_week: m.day_of_week || null,
    items: (m.items || []).map(it => ({
      food_id: it.food_id,
      food_name: it.food_name,
      quantity_g: it.quantity_g,
      kcal_per_100g: it.kcal_per_100g,
      protein_per_100g: it.protein_per_100g,
      carb_per_100g: it.carb_per_100g,
      fat_per_100g: it.fat_per_100g,
      notes: it.notes || '',
    })),
  }));

  const base = {
    /* === init data === */
    planId: plan ? plan.id : null,
    planKind: INIT.planKind || 'DAILY',
    folders: INIT.folders || [],
    clientsAll: INIT.clients || [],

    /* === Step 1 fields === */
    title: plan ? plan.title : '',
    description: plan ? plan.description : '',
    plan_type: plan ? plan.plan_type : '',
    nutrition_goal: plan ? plan.nutrition_goal : '',
    is_template: plan ? plan.is_template : false,
    daily_kcal: plan ? plan.daily_kcal : null,
    protein_target_g: plan ? plan.protein_target_g : null,
    carb_target_g: plan ? plan.carb_target_g : null,
    fat_target_g: plan ? plan.fat_target_g : null,
    folder_id: plan ? plan.folder_id : INIT.initialFolderId,

    /* === Step 2 state === */
    meals: seedMeals,
    activeDay: 'LUN',
    weekDays: [
      { code: 'LUN', label: 'Lun' },
      { code: 'MAR', label: 'Mar' },
      { code: 'MER', label: 'Mer' },
      { code: 'GIO', label: 'Gio' },
      { code: 'VEN', label: 'Ven' },
      { code: 'SAB', label: 'Sab' },
      { code: 'DOM', label: 'Dom' },
    ],

    /* === Step 3 state === */
    supplements: (INIT.supplements && INIT.supplements.items ? INIT.supplements.items : []).map((s, i) => ({
      _key: 's' + Date.now() + '_' + i,
      supplement_id: s.supplement_id,
      supplement_name: s.supplement_name || '',
      dose: s.dose || '',
      timing: s.timing || '',
      notes: s.notes || '',
    })),
    supplementNotes: (INIT.supplements && INIT.supplements.notes) || '',

    /* === Step 4 state === */
    recapDay: 'AVG',

    /* === wizard control === */
    step: 'info',
    stepDefs: [
      { id: 'info',        label: 'Informazioni', eyebrow: '01 · Info' },
      { id: 'builder',     label: 'Builder',      eyebrow: '02 · Pasti' },
      { id: 'integratori', label: 'Integrazione', eyebrow: '03 · Suppl.' },
      { id: 'riepilogo',   label: 'Riepilogo',    eyebrow: '04 · Assegna' },
    ],
    completedSteps: { info: false, builder: false, integratori: false, riepilogo: false },
    saving: false,
    errors: {},

    /* === assign modal state === */
    plans: [],
    assignModal: false,
    assignPlanId: null,
    assignPlanName: '',
    clientSearch: '',
    selectedClient: null,
    startDate: '',
    endDate: '',
    assignNotes: '',
    successFlash: false,

    init() {
      const params = new URLSearchParams(window.location.search);
      const requestedStep = params.get('step');
      if (this.planId) {
        this.completedSteps.info = true;
        this.completedSteps.builder = this.hasAnyMealWithItem();
        if (['info', 'builder', 'integratori', 'riepilogo'].includes(requestedStep)) {
          this.step = requestedStep;
        } else {
          this.step = 'builder';
        }
      }
    },

    /* === step navigation === */
    stepState(id) {
      if (this.step === id) return 'active';
      if (this.completedSteps[id]) return 'completed';
      const order = ['info', 'builder', 'integratori', 'riepilogo'];
      const curIdx = order.indexOf(this.step);
      const tgtIdx = order.indexOf(id);
      return tgtIdx < curIdx ? 'completed' : 'future';
    },
    canJump(id) {
      const order = ['info', 'builder', 'integratori', 'riepilogo'];
      const curIdx = order.indexOf(this.step);
      const tgtIdx = order.indexOf(id);
      if (tgtIdx <= curIdx) return true;
      if (id === 'builder')     return this.completedSteps.info;
      if (id === 'integratori') return this.completedSteps.info && this.completedSteps.builder;
      if (id === 'riepilogo')   return this.completedSteps.info && this.completedSteps.builder;
      return false;
    },
    jumpTo(id) {
      if (!this.canJump(id)) return;
      this.step = id;
      this.syncUrlStep();
    },
    stepBadgeStyle(id) {
      const st = this.stepState(id);
      if (st === 'active') {
        return 'width: 28px; height: 28px; background: var(--al-bronze); color: var(--al-parchment); border-radius: 999px;';
      }
      if (st === 'completed') {
        return 'width: 28px; height: 28px; background: var(--al-parchment); color: var(--al-bronze); border: 1.5px solid var(--al-bronze); border-radius: 999px;';
      }
      return 'width: 28px; height: 28px; background: var(--al-parchment); color: var(--al-ink-line); border: 1px solid var(--al-rule); border-radius: 999px;';
    },
    nextLabel() {
      if (this.step === 'info')        return 'Avanti';
      if (this.step === 'builder')     return 'Avanti';
      if (this.step === 'integratori') return 'Avanti';
      return 'Concludi';
    },
    syncUrlStep() {
      const params = new URLSearchParams(window.location.search);
      params.set('step', this.step);
      if (this.planKind) params.set('kind', this.planKind);
      const path = this.planId
        ? INIT.urls.editPattern.replace('__ID__', this.planId)
        : INIT.urls.create;
      history.replaceState(null, '', path + '?' + params.toString());
    },

    async goNext() {
      if (this.step === 'info') {
        if (!this.title.trim()) { this.errors = { title: 'Titolo obbligatorio.' }; return; }
        this.errors = {};
        const ok = await this.persist();
        if (!ok) return;
        this.completedSteps.info = true;
        this.step = 'builder';
        this.syncUrlStep();
        return;
      }
      if (this.step === 'builder') {
        if (!this.hasAnyMealWithItem()) {
          this.tryFallbackToast(this.planKind === 'WEEKLY'
            ? 'Compila almeno un giorno con un pasto.'
            : 'Aggiungi almeno un pasto con un alimento.');
          return;
        }
        const ok = await this.persist();
        if (!ok) return;
        this.completedSteps.builder = true;
        this.step = 'integratori';
        this.syncUrlStep();
        return;
      }
      if (this.step === 'integratori') {
        this.completedSteps.integratori = true;
        this.step = 'riepilogo';
        this.syncUrlStep();
        return;
      }
    },
    goBack() {
      const order = ['info', 'builder', 'integratori', 'riepilogo'];
      const i = order.indexOf(this.step);
      if (i > 0) { this.step = order[i - 1]; this.syncUrlStep(); }
    },
    skipIntegratori() {
      this.completedSteps.integratori = true;
      this.step = 'riepilogo';
      this.syncUrlStep();
    },

    /* === persistence === */
    async exitWithoutSaving() {
      const msg = this.planId
        ? 'Uscire senza salvare? Il piano in bozza verrà eliminato.'
        : 'Uscire senza salvare? Le modifiche non saranno conservate.';
      if (!confirm(msg)) return;
      if (this.planId) {
        try {
          await fetch(INIT.urls.deletePattern.replace('__ID__', this.planId), {
            method: 'POST',
            headers: { 'X-CSRFToken': window.nutCsrfToken() },
          });
        } catch (e) { /* still navigate away */ }
      }
      window.location.href = INIT.urls.piani;
    },
    async saveDraft() {
      if (this.step === 'info' && !this.title.trim()) {
        this.errors = { title: 'Titolo obbligatorio.' };
        return;
      }
      const ok = await this.persist();
      if (ok) this.tryFallbackToast('Bozza salvata.');
    },
    async persist() {
      this.saving = true;
      const url = this.planId
        ? INIT.urls.editPattern.replace('__ID__', this.planId)
        : INIT.urls.create;
      const payload = {
        title: this.title,
        description: this.description,
        plan_type: this.plan_type,
        plan_kind: this.planKind,
        nutrition_goal: this.nutrition_goal,
        is_template: !!this.is_template,
        daily_kcal: this.daily_kcal || null,
        protein_target_g: this.protein_target_g || null,
        carb_target_g: this.carb_target_g || null,
        fat_target_g: this.fat_target_g || null,
        folder_id: this.folder_id || null,
        meals: this.serializedMeals(),
      };
      try {
        const res = await fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': window.nutCsrfToken() },
          body: JSON.stringify(payload),
        });
        const data = await res.json().catch(() => ({}));
        this.saving = false;
        if (!res.ok) {
          this.tryFallbackToast(data.error || 'Errore di salvataggio.');
          return false;
        }
        if (!this.planId && data.plan_id) {
          this.planId = data.plan_id;
        }
        return true;
      } catch (e) {
        this.saving = false;
        this.tryFallbackToast('Errore di rete.');
        return false;
      }
    },
    serializedMeals() {
      return this.meals.map(m => ({
        name: m.name || '',
        time_of_day: m.time_of_day || '',
        notes: m.notes || '',
        day_of_week: this.planKind === 'WEEKLY' ? (m.day_of_week || null) : null,
        items: m.items.map(it => ({
          food_id: it.food_id,
          quantity_g: it.quantity_g,
          notes: it.notes || '',
        })),
      }));
    },
    async persistSupplements() {
      if (!this.planId) return;
      const items = this.supplements
        .filter(s => s.supplement_id)
        .map(s => ({
          supplement_id: s.supplement_id,
          dose: s.dose || '',
          timing: s.timing || '',
          notes: s.notes || '',
        }));
      try {
        await fetch(INIT.urls.supplementsPattern.replace('__ID__', this.planId), {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': window.nutCsrfToken() },
          body: JSON.stringify({ items, notes: this.supplementNotes || '' }),
        });
      } catch (e) {
        this.tryFallbackToast('Integratori non salvati.');
      }
    },

    /* === meal CRUD (DAILY/WEEKLY shared) === */
    addMeal() {
      const key = 'm' + Date.now() + '_' + Math.random().toString(36).slice(2, 6);
      const day = this.planKind === 'WEEKLY' ? this.activeDay : null;
      this.meals.push({
        _key: key,
        name: '',
        time_of_day: '',
        notes: '',
        day_of_week: day,
        items: [],
      });
    },
    removeMeal(key) {
      const i = this.meals.findIndex(m => m._key === key);
      if (i < 0) return;
      if (this.meals[i].items.length > 0) {
        if (!confirm('Eliminare il pasto e i suoi alimenti?')) return;
      }
      this.meals.splice(i, 1);
    },
    addFoodToMeal(mealKey, food) {
      const m = this.meals.find(x => x._key === mealKey);
      if (!m) return;
      m.items.push({
        food_id: food.id,
        food_name: food.name,
        quantity_g: 100,
        kcal_per_100g: food.kcal,
        protein_per_100g: food.protein,
        carb_per_100g: food.carb,
        fat_per_100g: food.fat,
        notes: '',
      });
    },
    currentDayMeals() {
      if (this.planKind === 'DAILY') return this.meals;
      return this.meals.filter(m => m.day_of_week === this.activeDay);
    },

    /* === side panel === */
    sidePanelKcal() {
      if (this.planKind === 'WEEKLY' && this.activeDay === 'AVG') return this.avgKcal();
      if (this.planKind === 'WEEKLY') return this.dayKcal(this.activeDay);
      return this.totalKcal();
    },
    sidePanelMacro(key) {
      if (this.planKind === 'WEEKLY' && this.activeDay === 'AVG') return this.avgMacro(key);
      if (this.planKind === 'WEEKLY') return this.dayMacro(this.activeDay, key);
      return this.totalMacro(key);
    },
    sidePanelMealCount() {
      if (this.planKind === 'WEEKLY' && this.activeDay === 'AVG') {
        const filled = this.filledDaysCount();
        return filled ? (this.meals.length / filled).toFixed(1) : '0';
      }
      if (this.planKind === 'WEEKLY') return this.dayMealCount(this.activeDay);
      return this.meals.length;
    },
    macroProgressPct(key, target) {
      const v = this.sidePanelMacro(key);
      const t = parseFloat(target);
      if (!t) return 0;
      return Math.min(100, Math.round((v / t) * 100));
    },
    kcalDeltaLabel() {
      const v = this.sidePanelKcal();
      const t = parseFloat(this.daily_kcal);
      if (!t) return '';
      const d = v - t;
      if (d === 0) return 'a target';
      return (d > 0 ? '+' : '') + d + ' kcal vs target';
    },
    kcalDeltaColor() {
      const v = this.sidePanelKcal();
      const t = parseFloat(this.daily_kcal);
      if (!t) return '';
      const pct = Math.abs((v - t) / t);
      if (pct <= 0.05) return 'color: var(--al-bronze);';
      if (pct <= 0.15) return 'color: var(--al-warn);';
      return 'color: var(--al-danger);';
    },

    /* === Step 3: supplements === */
    addSupplement() {
      this.supplements.push({
        _key: 's' + Date.now() + Math.random().toString(36).slice(2, 5),
        supplement_id: null,
        supplement_name: '',
        dose: '',
        timing: '',
        notes: '',
      });
    },
    removeSupplement(key) {
      const i = this.supplements.findIndex(s => s._key === key);
      if (i >= 0) this.supplements.splice(i, 1);
    },
    applySupplementPick(suppKey, supplement) {
      const target = this.supplements.find(x => x._key === suppKey);
      if (target) {
        target.supplement_id = supplement.id;
        target.supplement_name = supplement.name;
      }
    },

    /* === Step 4: riepilogo === */
    recapMeals() {
      if (this.planKind === 'DAILY') return this.meals;
      if (this.recapDay === 'AVG') return [];
      return this.meals.filter(m => m.day_of_week === this.recapDay);
    },
    riepilogoKcal() {
      if (this.planKind === 'WEEKLY') return this.avgKcal();
      return this.totalKcal();
    },
    riepilogoMacro(key) {
      if (this.planKind === 'WEEKLY') return this.avgMacro(key);
      return this.totalMacro(key);
    },
    deltaLabel(v, target) {
      const t = parseFloat(target);
      if (!t) return '';
      const d = v - t;
      if (d === 0) return 'a target';
      return (d > 0 ? '+' : '') + d;
    },
    deltaColorFor(v, target) {
      const t = parseFloat(target);
      if (!t) return '';
      const pct = Math.abs((v - t) / t);
      if (pct <= 0.05) return 'color: var(--al-bronze);';
      if (pct <= 0.15) return 'color: var(--al-warn);';
      return 'color: var(--al-danger);';
    },
    canAssign() {
      return !!this.title.trim() && this.hasAnyMealWithItem();
    },

    async finalize(mode) {
      if (!this.title.trim()) {
        this.tryFallbackToast('Titolo obbligatorio.');
        this.step = 'info';
        return;
      }
      if (mode === 'template') this.is_template = true;
      const ok = await this.persist();
      if (!ok) return;
      await this.persistSupplements();
      this.tryFallbackToast(mode === 'template' ? 'Template salvato.' : 'Bozza salvata.');
      window.location.href = INIT.urls.piani;
    },

    /* === Assign modal === */
    openAssign() {
      if (!this.canAssign()) return;
      this.persist().then(async ok => {
        if (!ok || !this.planId) return;
        await this.persistSupplements();
        this.assignPlanId = this.planId;
        this.assignPlanName = this.title;
        this.plans = [{ id: this.planId, title: this.title, assigned_client_ids: [] }];
        this.clientSearch = '';
        this.selectedClient = null;
        this.startDate = '';
        this.endDate = '';
        this.assignNotes = '';
        this.successFlash = false;
        this.assignModal = true;
      });
    },
    filteredClients() {
      const q = (this.clientSearch || '').toLowerCase();
      const plan = this.plans.find(p => p.id === this.assignPlanId);
      const blocked = new Set(plan ? (plan.assigned_client_ids || []) : []);
      return this.clientsAll
        .filter(c => !blocked.has(c.id))
        .filter(c => !q || c.name.toLowerCase().includes(q));
    },
    async submitAssign() {
      if (!this.selectedClient || !this.assignPlanId) return;
      this.saving = true;
      const res = await fetch(INIT.urls.assignPattern.replace('__ID__', this.assignPlanId), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRFToken': window.nutCsrfToken() },
        body: JSON.stringify({
          client_id: this.selectedClient.id,
          start_date: this.startDate || null,
          end_date: this.endDate || null,
          notes: this.assignNotes,
        }),
      });
      this.saving = false;
      if (res.ok) {
        this.successFlash = true;
        setTimeout(() => {
          this.assignModal = false;
          this.successFlash = false;
          window.location.href = INIT.urls.piani;
        }, 700);
      } else {
        this.tryFallbackToast('Errore durante l\'assegnazione.');
      }
    },

    tryFallbackToast(msg) {
      try {
        if (window.Alpine && Alpine.store && Alpine.store('toasts')) {
          Alpine.store('toasts').push({ kind: 'info', msg });
          return;
        }
      } catch (e) {}
      console.log('[wizard]', msg);
    },
  };

  const daily = (typeof window.nutritionWizardDailyMixin === 'function')
    ? window.nutritionWizardDailyMixin()
    : {};
  const weekly = (typeof window.nutritionWizardWeeklyMixin === 'function')
    ? window.nutritionWizardWeeklyMixin()
    : {};
  const charts = (typeof window.nutritionWizardChartsMixin === 'function')
    ? window.nutritionWizardChartsMixin()
    : {};

  return Object.assign({}, daily, weekly, charts, base);
}

/* Per-meal food search popover. */
function foodPicker(mealKey) {
  return {
    q: '', results: [], searching: false, show: false,
    top: '0px', left: '0px', width: '0px',
    updatePos() {
      const el = this.$refs.searchBar;
      if (!el) return;
      const r = el.getBoundingClientRect();
      this.top = (r.bottom + 6) + 'px';
      this.left = r.left + 'px';
      this.width = r.width + 'px';
    },
    async search() {
      if (this.q.length < 2) { this.results = []; this.show = false; return; }
      this.searching = true;
      this.updatePos();
      try {
        const r = await fetch(window.NUTRITION_WIZARD_INIT.urls.foodSearch + '?q=' + encodeURIComponent(this.q));
        const d = await r.json();
        this.results = d.results || [];
      } catch (e) { this.results = []; }
      this.searching = false;
      this.show = true;
    },
    pick(food) {
      window.dispatchEvent(new CustomEvent('add-food', { detail: { mealKey, food } }));
      this.q = ''; this.results = []; this.show = false;
    },
  };
}

/* Per-row supplement search popover. Bubbles via window event. */
function supplementPicker(suppKey, initialName) {
  return {
    q: initialName || '', results: [], show: false,
    top: '0px', left: '0px', width: '0px',
    updatePos() {
      const el = this.$refs.searchBar;
      if (!el) return;
      const r = el.getBoundingClientRect();
      this.top = (r.bottom + 6) + 'px';
      this.left = r.left + 'px';
      this.width = r.width + 'px';
    },
    async search() {
      if (this.q.length < 2) { this.results = []; this.show = false; return; }
      this.updatePos();
      try {
        const r = await fetch(window.NUTRITION_WIZARD_INIT.urls.supplementSearch + '?q=' + encodeURIComponent(this.q));
        const d = await r.json();
        this.results = d.results || [];
      } catch (e) { this.results = []; }
      this.show = true;
    },
    pick(s) {
      window.dispatchEvent(new CustomEvent('pick-supplement', { detail: { suppKey, supplement: s } }));
      this.q = s.name; this.results = []; this.show = false;
    },
  };
}

window.nutritionWizard = nutritionWizard;
window.foodPicker = foodPicker;
window.supplementPicker = supplementPicker;
