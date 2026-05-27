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
    items: (m.items || []).map((it, j) => ({
      _key: 'i' + Date.now() + '_' + i + '_' + j,
      food_id: it.food_id,
      food_name: it.food_name,
      quantity_g: it.quantity_g,
      kcal_per_100g: it.kcal_per_100g,
      protein_per_100g: it.protein_per_100g,
      carb_per_100g: it.carb_per_100g,
      fat_per_100g: it.fat_per_100g,
      fiber_per_100g: it.fiber_per_100g || 0,
      sat_fat_per_100g: it.sat_fat_per_100g || 0,
      cholesterol_per_100g: it.cholesterol_per_100g || 0,
      sugars_per_100g: it.sugars_per_100g || 0,
      iron_per_100g: it.iron_per_100g || 0,
      calcium_per_100g: it.calcium_per_100g || 0,
      sodium_per_100g: it.sodium_per_100g || 0,
      potassium_per_100g: it.potassium_per_100g || 0,
      phosphorus_per_100g: it.phosphorus_per_100g || 0,
      zinc_per_100g: it.zinc_per_100g || 0,
      magnesium_per_100g: it.magnesium_per_100g || 0,
      copper_per_100g: it.copper_per_100g || 0,
      selenium_per_100g: it.selenium_per_100g || 0,
      iodine_per_100g: it.iodine_per_100g || 0,
      manganese_per_100g: it.manganese_per_100g || 0,
      vit_b1_per_100g: it.vit_b1_per_100g || 0,
      vit_b2_per_100g: it.vit_b2_per_100g || 0,
      vit_c_per_100g: it.vit_c_per_100g || 0,
      niacin_per_100g: it.niacin_per_100g || 0,
      vit_b6_per_100g: it.vit_b6_per_100g || 0,
      folate_per_100g: it.folate_per_100g || 0,
      vit_b12_per_100g: it.vit_b12_per_100g || 0,
      isoleucine_per_100g: it.isoleucine_per_100g || 0,
      leucine_per_100g: it.leucine_per_100g || 0,
      valine_per_100g: it.valine_per_100g || 0,
      lactose_per_100g: it.lactose_per_100g || 0,
      notes: it.notes || '',
      subsOpen: false,
      addSubMode: null,
      substitutions: (it.substitutions || []).map(s => ({
        food_id: s.food_id,
        food_name: s.food_name,
        mode: s.mode,
        quantity_g: s.quantity_g,
        kcal_per_100g: s.kcal_per_100g,
        protein_per_100g: s.protein_per_100g,
        carb_per_100g: s.carb_per_100g,
        fat_per_100g: s.fat_per_100g,
      })),
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
    /* volatile: drives g/kg + kcal/kg calculator in builder sidebar, never persisted */
    calc_weight_kg: null,
    folder_id: plan ? plan.folder_id : INIT.initialFolderId,
    include_substitutions_in_avg: plan ? !!plan.include_substitutions_in_avg : false,

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

    /* === micro panel state === */
    microFlipped: false,
    microFlipping: false,

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
      /* Track whether the plan started this session (no prior persistence) so
         "Esci senza salvare" knows whether to delete vs. restore.            */
      this._createdInSession = !this.planId;
      if (this.planId) {
        this.completedSteps.info = true;
        this.completedSteps.builder = this.hasAnyMealWithItem();
        if (['info', 'builder', 'integratori', 'riepilogo'].includes(requestedStep)) {
          this.step = requestedStep;
        } else {
          this.step = 'builder';
        }
        /* Snapshot the loaded state so exit-without-saving can restore it. */
        this._originalSnapshot = this._snapshotState();
      } else {
        this._originalSnapshot = null;
      }
    },

    _snapshotState() {
      return {
        title: this.title,
        description: this.description,
        plan_type: this.plan_type,
        nutrition_goal: this.nutrition_goal,
        is_template: this.is_template,
        daily_kcal: this.daily_kcal,
        protein_target_g: this.protein_target_g,
        carb_target_g: this.carb_target_g,
        fat_target_g: this.fat_target_g,
        folder_id: this.folder_id,
        include_substitutions_in_avg: this.include_substitutions_in_avg,
        meals: JSON.parse(JSON.stringify(this.meals)),
        supplements: JSON.parse(JSON.stringify(this.supplements)),
        supplementNotes: this.supplementNotes,
      };
    },

    _restoreSnapshot(s) {
      this.title = s.title;
      this.description = s.description;
      this.plan_type = s.plan_type;
      this.nutrition_goal = s.nutrition_goal;
      this.is_template = s.is_template;
      this.daily_kcal = s.daily_kcal;
      this.protein_target_g = s.protein_target_g;
      this.carb_target_g = s.carb_target_g;
      this.fat_target_g = s.fat_target_g;
      this.folder_id = s.folder_id;
      this.include_substitutions_in_avg = s.include_substitutions_in_avg;
      this.meals = JSON.parse(JSON.stringify(s.meals));
      this.supplements = JSON.parse(JSON.stringify(s.supplements));
      this.supplementNotes = s.supplementNotes;
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
      /* Two distinct cases:
           - Plan created in THIS session (no prior persistence): delete it.
           - Plan loaded from a previous session: restore the snapshot taken
             at init, undoing every change persisted via Avanti / Salva bozza
             during this edit session. The original draft survives untouched.   */
      const createdNow = this._createdInSession;
      const msg = createdNow
        ? 'Uscire senza salvare? Il piano appena creato verrà eliminato.'
        : 'Annullare le modifiche di questa sessione? Verrà ripristinata l\'ultima versione salvata.';
      if (!confirm(msg)) return;

      this.saving = true;
      try {
        if (createdNow) {
          if (this.planId) {
            await fetch(INIT.urls.deletePattern.replace('__ID__', this.planId), {
              method: 'POST',
              headers: { 'X-CSRFToken': window.nutCsrfToken() },
            });
          }
        } else if (this.planId && this._originalSnapshot) {
          this._restoreSnapshot(this._originalSnapshot);
          await this.persist();
          await this.persistSupplements();
        }
      } catch (e) {
        /* swallow — user explicitly chose to leave; navigate regardless */
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
        include_substitutions_in_avg: !!this.include_substitutions_in_avg,
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
          substitutions: (it.substitutions || []).map(s => ({
            food_id: s.food_id,
            mode: s.mode,
            quantity_g: s.quantity_g,
          })),
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
        _key: 'i' + Date.now() + '_' + Math.random().toString(36).slice(2, 6),
        food_id: food.id,
        food_name: food.name,
        quantity_g: 100,
        kcal_per_100g: food.kcal,
        protein_per_100g: food.protein,
        carb_per_100g: food.carb,
        fat_per_100g: food.fat,
        fiber_per_100g: food.fiber || 0,
        sat_fat_per_100g: food.sat_fat || 0,
        cholesterol_per_100g: food.cholesterol || 0,
        sugars_per_100g: food.sugars || 0,
        iron_per_100g: food.iron || 0,
        calcium_per_100g: food.calcium || 0,
        sodium_per_100g: food.sodium || 0,
        potassium_per_100g: food.potassium || 0,
        phosphorus_per_100g: food.phosphorus || 0,
        zinc_per_100g: food.zinc || 0,
        magnesium_per_100g: food.magnesium || 0,
        copper_per_100g: food.copper || 0,
        selenium_per_100g: food.selenium || 0,
        iodine_per_100g: food.iodine || 0,
        manganese_per_100g: food.manganese || 0,
        vit_b1_per_100g: food.vit_b1 || 0,
        vit_b2_per_100g: food.vit_b2 || 0,
        vit_c_per_100g: food.vit_c || 0,
        niacin_per_100g: food.niacin || 0,
        vit_b6_per_100g: food.vit_b6 || 0,
        folate_per_100g: food.folate || 0,
        vit_b12_per_100g: food.vit_b12 || 0,
        isoleucine_per_100g: food.isoleucine || 0,
        leucine_per_100g: food.leucine || 0,
        valine_per_100g: food.valine || 0,
        lactose_per_100g: food.lactose || 0,
        notes: '',
        subsOpen: false,
        addSubMode: null,
        substitutions: [],
      });
    },

    /* === substitution CRUD === */
    roundTo5(g) {
      const v = Math.round((parseFloat(g) || 0) / 5) * 5;
      return Math.max(5, v);
    },
    /* Returns null when the chosen mode cannot apply (e.g. iso-prot on a 0g-protein food). */
    computeSubGrams(item, food, mode) {
      const q = parseFloat(item.quantity_g) || 0;
      if (mode === 'ISOKCAL') {
        const target = item.kcal_per_100g * q / 100;
        if (!food.kcal) return null;
        return this.roundTo5(target / food.kcal * 100);
      }
      if (mode === 'ISOPROT') {
        const target = item.protein_per_100g * q / 100;
        if (!food.protein) return null;
        return this.roundTo5(target / food.protein * 100);
      }
      if (mode === 'ISOCARB') {
        const target = item.carb_per_100g * q / 100;
        if (!food.carb) return null;
        return this.roundTo5(target / food.carb * 100);
      }
      return null;
    },
    addSubstitutionToItem(mealKey, itemKey, mode, food) {
      const m = this.meals.find(x => x._key === mealKey);
      if (!m) return;
      const it = m.items.find(x => x._key === itemKey);
      if (!it) return;
      const grams = this.computeSubGrams(it, food, mode);
      if (grams === null) {
        this.tryFallbackToast('Sostituzione non applicabile: macro target a zero.');
        return;
      }
      it.substitutions.push({
        food_id: food.id,
        food_name: food.name,
        mode,
        quantity_g: grams,
        kcal_per_100g: food.kcal,
        protein_per_100g: food.protein,
        carb_per_100g: food.carb,
        fat_per_100g: food.fat,
      });
      it.subsOpen = true;
      it.addSubMode = null;
    },
    removeSubstitution(item, idx) {
      if (idx >= 0 && idx < item.substitutions.length) item.substitutions.splice(idx, 1);
    },
    subMacros(sub) {
      const q = parseFloat(sub.quantity_g) || 0;
      const k = Math.round(sub.kcal_per_100g * q / 100);
      const p = (sub.protein_per_100g * q / 100).toFixed(1);
      const c = (sub.carb_per_100g * q / 100).toFixed(1);
      const f = (sub.fat_per_100g * q / 100).toFixed(1);
      return k + ' kcal · P ' + p + ' · C ' + c + ' · F ' + f;
    },
    subModeLabel(mode) {
      return mode === 'ISOKCAL' ? 'iso-kcal'
        : mode === 'ISOPROT' ? 'iso-prot'
        : mode === 'ISOCARB' ? 'iso-carb' : mode;
    },
    subModeColor(mode) {
      if (mode === 'ISOKCAL') return 'var(--al-bronze)';
      if (mode === 'ISOPROT') return 'var(--al-aegean)';
      if (mode === 'ISOCARB') return 'var(--al-warn)';
      return 'var(--al-ink-mute)';
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

    /* === micro panel === */
    toggleMicro() {
      if (this.microFlipping) return;
      const self = this;
      self.microFlipping = true;
      setTimeout(() => {
        self.microFlipped = !self.microFlipped;
        setTimeout(() => { self.microFlipping = false; }, 50);
      }, 160);
    },
    microVal(key) {
      /* Returns the daily total (or avg) for any _per_100g nutrient key */
      return parseFloat(this.sidePanelMacro(key).toFixed ? this.sidePanelMacro(key) : 0) || 0;
    },
    microDefs() {
      return [
        { group: 'Latticini', color: 'var(--al-bronze)', items: [
          { key: 'lactose',    label: 'Lattosio',   unit: 'g'  },
        ]},
        { group: 'Minerali', color: 'var(--al-aegean)', items: [
          { key: 'iron',       label: 'Ferro',      unit: 'mg' },
          { key: 'calcium',    label: 'Calcio',     unit: 'mg' },
          { key: 'sodium',     label: 'Sodio',      unit: 'mg' },
          { key: 'potassium',  label: 'Potassio',   unit: 'mg' },
          { key: 'phosphorus', label: 'Fosforo',    unit: 'mg' },
          { key: 'zinc',       label: 'Zinco',      unit: 'mg' },
          { key: 'magnesium',  label: 'Magnesio',   unit: 'mg' },
          { key: 'copper',     label: 'Rame',       unit: 'mg' },
          { key: 'selenium',   label: 'Selenio',    unit: 'μg' },
          { key: 'iodine',     label: 'Iodio',      unit: 'μg' },
          { key: 'manganese',  label: 'Manganese',  unit: 'mg' },
        ]},
        { group: 'Vitamine', color: 'var(--al-warn)', items: [
          { key: 'vit_b1',    label: 'Vit. B1',    unit: 'mg' },
          { key: 'vit_b2',    label: 'Vit. B2',    unit: 'mg' },
          { key: 'vit_c',     label: 'Vit. C',     unit: 'mg' },
          { key: 'niacin',    label: 'Niacina',    unit: 'mg' },
          { key: 'vit_b6',    label: 'Vit. B6',    unit: 'mg' },
          { key: 'folate',    label: 'Folati',     unit: 'μg' },
          { key: 'vit_b12',   label: 'Vit. B12',   unit: 'μg' },
        ]},
        { group: 'Amminoacidi', color: 'var(--al-danger)', items: [
          { key: 'isoleucine', label: 'Isoleucina', unit: 'mg' },
          { key: 'leucine',    label: 'Leucina',    unit: 'mg' },
          { key: 'valine',     label: 'Valina',     unit: 'mg' },
        ]},
      ];
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

/* Substitution food picker — same UX as foodPicker, but bubbles the chosen food
   plus the substitution mode so the wizard can compute grams server-side rules. */
function substitutionPicker(mealKey, itemKey, mode) {
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
      window.dispatchEvent(new CustomEvent('add-sub', {
        detail: { mealKey, itemKey, mode, food },
      }));
      this.q = ''; this.results = []; this.show = false;
    },
  };
}

window.nutritionWizard = nutritionWizard;
window.foodPicker = foodPicker;
window.supplementPicker = supplementPicker;
window.substitutionPicker = substitutionPicker;
