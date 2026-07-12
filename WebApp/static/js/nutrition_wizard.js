/* Athlynk · Nutrition Wizard · main Alpine component
   Backs pages/nutrizione/piano_create.html. Init data comes from
   window.NUTRITION_WIZARD_INIT. DAILY + WEEKLY behaviour is split into
   nutrition_wizard_builder_daily.js / _weekly.js mixins. */

(function () {
  if (!window.nutCsrfToken) {
    window.nutCsrfToken = function () {
      return window.csrfToken()
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

  /* MACRO mode: per-weekday target store keyed by short day code. Seeded from
     INIT.dayTargets (sparse) so only the days the coach filled are pre-loaded. */
  const DAY_CODES = ['LUN', 'MAR', 'MER', 'GIO', 'VEN', 'SAB', 'DOM'];
  const macroDayTargets = {};
  DAY_CODES.forEach(c => { macroDayTargets[c] = { kcal: null, protein: null, carb: null, fat: null }; });
  (INIT.dayTargets || []).forEach(dt => {
    const c = dt.day_of_week;
    if (macroDayTargets[c]) {
      macroDayTargets[c] = {
        kcal: dt.kcal ?? null,
        protein: dt.protein ?? null,
        carb: dt.carb ?? null,
        fat: dt.fat ?? null,
      };
    }
  });

  const base = {
    /* === init data === */
    planId: plan ? plan.id : null,
    planKind: INIT.planKind || 'DAILY',
    planMode: INIT.planMode || 'FOOD',
    macroDayTargets: macroDayTargets,
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
      name: s.name || '',
      quantity: s.quantity || '',
      unit: s.unit || 'g',
      timing: s.timing || '',
      notes: s.notes || '',
      _invalid: false,
      _shake: false,
    })),
    supplementNotes: (INIT.supplements && INIT.supplements.notes) || '',

    /* === Step 3: multi-select bulk actions === */
    selectedSuppKeys: [],

    /* === Step 3: import-from-protocol panel + whole-sheet save tracking === */
    suppModelsOpen: false,
    suppModelsLoading: false,
    suppProtocols: [],
    suppSavedSnapshot: null,   // JSON string of last-saved {items, notes}; null until first save
    suppSaving: false,

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
    overwriteConfirmed: false,

    /* === fabbisogni suggestion state === */
    fabbisogniData: null,
    fabbisogniLoading: false,
    // Info-step "Hai già calcolato i fabbisogni?" card
    fabCardOpen: false,
    fabSearch: '',
    fabClient: null,        // athlete picked in the info-step card
    fabPicked: false,       // a client was chosen (distinguishes "none" from "not yet")
    fabApplied: false,      // targets pulled into the plan

    init() {
      const params = new URLSearchParams(window.location.search);
      const requestedStep = params.get('step');
      /* MACRO plans set targets, not meals — relabel step 2 accordingly. */
      if (this.planMode === 'MACRO') {
        const s = this.stepDefs.find(d => d.id === 'builder');
        if (s) { s.label = 'Obiettivi'; s.eyebrow = '02 · Macro'; }
      }
      /* Track whether the plan started this session (no prior persistence) so
         "Esci senza salvare" knows whether to delete vs. restore.            */
      this._createdInSession = !this.planId;
      if (this.planId) {
        this.completedSteps.info = true;
        this.completedSteps.builder = this.builderComplete();
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
      this.suppSavedSnapshot = this._suppSerialize();
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
        macroDayTargets: JSON.parse(JSON.stringify(this.macroDayTargets)),
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
      if (s.macroDayTargets) this.macroDayTargets = JSON.parse(JSON.stringify(s.macroDayTargets));
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
      // Leaving integratori for a later step requires every row to be named.
      if (this.step === 'integratori' && id === 'riepilogo' && !this.validateSupplements()) return;
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
        if (!this.builderComplete()) {
          if (this.planMode === 'MACRO') {
            this.tryFallbackToast(this.planKind === 'WEEKLY'
              ? 'Imposta gli obiettivi macro per almeno un giorno.'
              : 'Imposta almeno un obiettivo macro.');
          } else {
            this.tryFallbackToast(this.planKind === 'WEEKLY'
              ? 'Compila almeno un giorno con un pasto.'
              : 'Aggiungi almeno un pasto con un alimento.');
          }
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
        if (!this.validateSupplements()) return;
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
      const ok = await window.alConfirm(createdNow
        ? { icon: 'ph-trash', title: 'Uscire senza\nsalvare?', subtitle: 'Il piano appena creato verrà eliminato.', confirmLabel: 'Sì, esci' }
        : { variant: 'neutral', icon: 'ph-arrow-counter-clockwise', title: 'Annullare le\nmodifiche?', subtitle: 'Verrà ripristinata l\'ultima versione salvata.', confirmLabel: 'Sì, annulla' });
      if (!ok) return;

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
        plan_mode: this.planMode,
        nutrition_goal: this.nutrition_goal,
        is_template: !!this.is_template,
        daily_kcal: this.daily_kcal || null,
        protein_target_g: this.protein_target_g || null,
        carb_target_g: this.carb_target_g || null,
        fat_target_g: this.fat_target_g || null,
        folder_id: this.folder_id || null,
        include_substitutions_in_avg: !!this.include_substitutions_in_avg,
        meals: this.planMode === 'MACRO' ? [] : this.serializedMeals(),
        day_targets: (this.planMode === 'MACRO' && this.planKind === 'WEEKLY')
          ? this.serializedDayTargets() : [],
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
    _suppSerialize() {
      return JSON.stringify(this.supplements
        .filter(s => (s.name || '').trim())
        .map(s => ({
          name: s.name, quantity: s.quantity || '', unit: s.unit || '',
          timing: s.timing || '', notes: s.notes || '',
        })));
    },
    suppIsDirty() {
      return this._suppSerialize() !== this.suppSavedSnapshot;
    },
    async saveSupplementSheet() {
      if (!this.supplements.length) return;
      this.suppSaving = true;
      const ok = await this.persist();
      if (ok) await this.persistSupplements();
      this.suppSaving = false;
    },
    async persistSupplements() {
      if (!this.planId) return;
      const items = this.supplements
        .filter(s => (s.name || '').trim())
        .map(s => ({
          name: s.name,
          quantity: s.quantity || '',
          unit: s.unit || '',
          timing: s.timing || '',
          notes: s.notes || '',
        }));
      try {
        await fetch(INIT.urls.supplementsPattern.replace('__ID__', this.planId), {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': window.nutCsrfToken() },
          body: JSON.stringify({ items, notes: this.supplementNotes || '' }),
        });
        this.suppSavedSnapshot = this._suppSerialize();
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
    async removeMeal(key) {
      const i = this.meals.findIndex(m => m._key === key);
      if (i < 0) return;
      if (this.meals[i].items.length > 0) {
        if (!await window.alConfirm({ icon: 'ph-trash', title: 'Eliminare il\npasto?', subtitle: 'Il pasto e tutti i suoi alimenti verranno rimossi.', confirmLabel: 'Sì, elimina' })) return;
      }
      this.meals.splice(i, 1);
    },
    /* === Add-food slide-in panel === */
    foodPanel: {
      open: false, mealKey: null, q: '', filter: 'all', activeCat: '',
      categories: [], results: [], searching: false, justAdded: null,
      hasMore: false, loadingMore: false,
    },
    openFoodPanel(mealKey) {
      this.foodPanel.mealKey = mealKey;
      this.foodPanel.q = ''; this.foodPanel.filter = 'all'; this.foodPanel.activeCat = '';
      this.foodPanel.results = []; this.foodPanel.open = true;
      this.foodPanelSearch(this.foodPanel.categories.length === 0);
    },
    closeFoodPanel() { this.foodPanel.open = false; },
    setFoodFilter(f) {
      this.foodPanel.filter = f; this.foodPanel.activeCat = '';
      if (f === 'cat') { this.foodPanel.results = []; this.foodPanelSearch(this.foodPanel.categories.length === 0); }
      else { this.foodPanelSearch(); }
    },
    pickFoodCat(cat) { this.foodPanel.activeCat = cat; this.foodPanelSearch(); },
    async foodPanelSearch(loadCats = false) {
      const p = this.foodPanel;
      if (p.filter === 'cat' && !p.activeCat && !loadCats) { p.results = []; return; }
      p.searching = true;
      const u = new URL(window.NUTRITION_WIZARD_INIT.urls.foodSearch, window.location.origin);
      if (p.q) u.searchParams.set('q', p.q);
      if (p.filter === 'recent') u.searchParams.set('filter', 'recent');
      if (p.filter === 'cat' && p.activeCat) u.searchParams.set('cat', p.activeCat);
      if (loadCats) u.searchParams.set('include_cats', '1');
      try {
        const r = await fetch(u);
        const d = await r.json();
        p.results = d.results || [];
        p.hasMore = !!d.has_more;
        if (d.categories) p.categories = d.categories;
        // In "Categorie" mode, don't dump foods until a category is chosen.
        if (p.filter === 'cat' && !p.activeCat) { p.results = []; p.hasMore = false; }
      } catch (e) { p.results = []; p.hasMore = false; }
      p.searching = false;
    },
    async foodPanelLoadMore() {
      const p = this.foodPanel;
      if (p.loadingMore || !p.hasMore || p.searching) return;
      if (p.filter === 'recent') return;
      if (p.filter === 'cat' && !p.activeCat) return;
      p.loadingMore = true;
      const u = new URL(window.NUTRITION_WIZARD_INIT.urls.foodSearch, window.location.origin);
      if (p.q) u.searchParams.set('q', p.q);
      if (p.filter === 'cat' && p.activeCat) u.searchParams.set('cat', p.activeCat);
      u.searchParams.set('offset', p.results.length);
      try {
        const r = await fetch(u);
        const d = await r.json();
        p.results = p.results.concat(d.results || []);
        p.hasMore = !!d.has_more;
      } catch (e) { p.hasMore = false; }
      p.loadingMore = false;
    },
    onFoodScroll(e) {
      const el = e.target;
      if (el.scrollHeight - el.scrollTop - el.clientHeight < 140) this.foodPanelLoadMore();
    },
    addFromPanel(food) {
      this.addFoodToMeal(this.foodPanel.mealKey, food);
      const id = food.id;
      this.foodPanel.justAdded = id;
      setTimeout(() => { if (this.foodPanel.justAdded === id) this.foodPanel.justAdded = null; }, 900);
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

    /* ============================================================
       MACRO mode — coach sets only the targets the client must hit.
       ============================================================ */
    builderComplete() {
      return this.planMode === 'MACRO' ? this.hasAnyMacroTarget() : this.hasAnyMealWithItem();
    },
    /* Coerce a target field to a non-negative integer in place. */
    sanitizeTarget(obj, key) {
      let v = obj[key];
      if (v === '' || v === null || v === undefined) { obj[key] = null; return; }
      v = Math.floor(Number(v));
      if (isNaN(v) || v < 0) v = 0;
      obj[key] = v;
    },
    /* The target object currently being edited / displayed. */
    currentMacroTarget() {
      if (this.planKind === 'DAILY') {
        return { kcal: this.daily_kcal, protein: this.protein_target_g,
                 carb: this.carb_target_g, fat: this.fat_target_g };
      }
      if (this.activeDay === 'AVG') return this.macroAvgTarget();
      return this.macroDayTargets[this.activeDay] || { kcal: null, protein: null, carb: null, fat: null };
    },
    dayTargetHasValue(code) {
      const t = this.macroDayTargets[code];
      if (!t) return false;
      return [t.kcal, t.protein, t.carb, t.fat].some(v => v !== null && v !== '' && Number(v) > 0);
    },
    macroFilledDays() {
      return this.weekDays.filter(d => this.dayTargetHasValue(d.code)).length;
    },
    hasAnyMacroTarget() {
      if (this.planKind === 'DAILY') {
        return [this.daily_kcal, this.protein_target_g, this.carb_target_g, this.fat_target_g]
          .some(v => v !== null && v !== '' && Number(v) > 0);
      }
      return this.macroFilledDays() > 0;
    },
    macroAvgTarget() {
      const filled = this.weekDays.filter(d => this.dayTargetHasValue(d.code));
      const n = filled.length || 0;
      const sum = { kcal: 0, protein: 0, carb: 0, fat: 0 };
      filled.forEach(d => {
        const t = this.macroDayTargets[d.code];
        sum.kcal += Number(t.kcal) || 0;
        sum.protein += Number(t.protein) || 0;
        sum.carb += Number(t.carb) || 0;
        sum.fat += Number(t.fat) || 0;
      });
      if (!n) return { kcal: null, protein: null, carb: null, fat: null };
      return {
        kcal: Math.round(sum.kcal / n), protein: Math.round(sum.protein / n),
        carb: Math.round(sum.carb / n), fat: Math.round(sum.fat / n),
      };
    },
    /* Duplicate the active day's targets onto another day. */
    copyMacroDayFrom(srcCode) {
      const src = this.macroDayTargets[srcCode];
      if (!src) return;
      this.macroDayTargets[this.activeDay] = {
        kcal: src.kcal, protein: src.protein, carb: src.carb, fat: src.fat,
      };
    },
    /* Donut segments for the target currently shown (reuses the shared
       macroPieSegments helper, sized by kcal contribution prot×4/carb×4/fat×9). */
    currentMacroSegments() {
      const t = this.currentMacroTarget();
      return this.macroPieSegments(t.protein, t.carb, t.fat);
    },
    /* Sum of macro-derived kcal for the current target (prot×4 + carb×4 + fat×9). */
    currentMacroKcal() {
      const t = this.currentMacroTarget();
      return Math.round((Number(t.protein) || 0) * 4 + (Number(t.carb) || 0) * 4 + (Number(t.fat) || 0) * 9);
    },
    serializedDayTargets() {
      const out = [];
      this.weekDays.forEach(d => {
        const t = this.macroDayTargets[d.code];
        if (!t) return;
        const has = [t.kcal, t.protein, t.carb, t.fat].some(v => v !== null && v !== '' && Number(v) > 0);
        if (!has) return;
        out.push({
          day_of_week: d.code,
          kcal: t.kcal || null, protein: t.protein || null,
          carb: t.carb || null, fat: t.fat || null,
        });
      });
      return out;
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

    /* === Step 3: supplements (free-text) === */
    addSupplement() {
      this.supplements.push({
        _key: 's' + Date.now() + Math.random().toString(36).slice(2, 5),
        name: '',
        quantity: '',
        unit: 'g',
        timing: '',
        notes: '',
        _invalid: false,
        _shake: false,
      });
    },
    async removeSupplement(key) {
      const i = this.supplements.findIndex(s => s._key === key);
      if (i < 0) return;
      const label = (this.supplements[i].name || '').trim() || 'questo integratore';
      const ok = window.alConfirm ? await window.alConfirm({
        icon: 'ph-trash', title: 'Eliminare\nl\'integratore?',
        subtitle: '«' + label + '» verrà rimosso.', confirmLabel: 'Sì, elimina',
      }) : confirm('Eliminare «' + label + '»?');
      if (ok) {
        this.supplements.splice(i, 1);
        this.selectedSuppKeys = this.selectedSuppKeys.filter(k => k !== key);
      }
    },
    toggleSelectSupp(key) {
      const i = this.selectedSuppKeys.indexOf(key);
      if (i >= 0) this.selectedSuppKeys.splice(i, 1);
      else this.selectedSuppKeys.push(key);
    },
    async bulkDeleteSupplements() {
      const n = this.selectedSuppKeys.length;
      if (n === 0) return;
      const ok = window.alConfirm
        ? await window.alConfirm({ icon: 'ph-trash', title: `Eliminare ${n} integrator${n === 1 ? 'e' : 'i'}?`,
            subtitle: 'Gli elementi selezionati verranno rimossi.', confirmLabel: 'Sì, elimina' })
        : confirm(`Eliminare ${n} integratori selezionati?`);
      if (!ok) return;
      this.supplements = this.supplements.filter(s => !this.selectedSuppKeys.includes(s._key));
      this.selectedSuppKeys = [];
    },

    /* --- import da un protocollo esistente (scheda intera) --- */
    async openSupplementModels() {
      this.suppModelsOpen = true;
      await this.loadSupplementModels();
    },
    async loadSupplementModels() {
      this.suppModelsLoading = true;
      try {
        const r = await fetch('/api/nutrizione/integratori/schede/lista/');
        const d = await r.json().catch(() => ({ results: [] }));
        this.suppProtocols = d.results || [];
      } catch (_) { this.suppProtocols = []; }
      this.suppModelsLoading = false;
    },
    importProtocol(p) {
      (p.items || []).forEach(it => {
        this.supplements.push({
          _key: 's' + Date.now() + Math.random().toString(36).slice(2, 5),
          name: it.name || '', quantity: it.quantity || '', unit: it.unit || 'g',
          timing: it.timing || '', notes: it.notes || '', _invalid: false, _shake: false,
        });
      });
      this.suppModelsOpen = false;
    },
    /* Block leaving the integratori step with nameless rows: flag + shake them. */
    validateSupplements() {
      let hasBad = false;
      this.supplements.forEach(s => {
        const bad = !(s.name || '').trim();
        s._invalid = bad;
        s._shake = false;
        if (bad) hasBad = true;
      });
      if (hasBad) {
        this.$nextTick(() => {
          this.supplements.forEach(s => { if (s._invalid) s._shake = true; });
          setTimeout(() => { this.supplements.forEach(s => { s._shake = false; }); }, 450);
        });
        return false;
      }
      return true;
    },

    /* === Step 4: riepilogo === */
    recapMeals() {
      if (this.planKind === 'DAILY') return this.meals;
      if (this.recapDay === 'AVG') return [];
      return this.meals.filter(m => m.day_of_week === this.recapDay);
    },
    riepilogoKcal() {
      if (this.planMode === 'MACRO') {
        if (this.planKind === 'WEEKLY') return this.macroAvgTarget().kcal || 0;
        return this.daily_kcal || 0;
      }
      if (this.planKind === 'WEEKLY') return this.avgKcal();
      return this.totalKcal();
    },
    riepilogoMacro(key) {
      if (this.planMode === 'MACRO') {
        if (this.planKind === 'WEEKLY') return this.macroAvgTarget()[key] || 0;
        const map = { protein: this.protein_target_g, carb: this.carb_target_g, fat: this.fat_target_g };
        return map[key] || 0;
      }
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
      return !!this.title.trim() && this.builderComplete();
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

    /* === Fabbisogni suggestion === */
    async loadClientFabbisogni(clientId) {
      this.fabbisogniData = null;
      if (!clientId || !INIT.urls.fabbisogniPattern) return;
      this.fabbisogniLoading = true;
      try {
        const url = INIT.urls.fabbisogniPattern.replace('__CLIENT_ID__', clientId);
        const res = await fetch(url, { credentials: 'same-origin' });
        if (res.ok) {
          const json = await res.json();
          this.fabbisogniData = json.fresh ? json : null;
        }
      } catch (e) { /* silently ignore */ }
      this.fabbisogniLoading = false;
    },
    applyFabbisogniTargets() {
      const d = this.fabbisogniData && this.fabbisogniData.data;
      if (!d) return;
      if (d.det_kcal)      this.daily_kcal      = d.det_kcal;
      if (d.proteine_g)    this.protein_target_g = d.proteine_g;
      if (d.carboidrati_g) this.carb_target_g    = d.carboidrati_g;
      if (d.lipidi_g)      this.fat_target_g     = d.lipidi_g;
      this.fabApplied = true;
    },

    /* Info-step card: pick an athlete and pull their computed fabbisogni. */
    fabClientsAll() {
      return this.clientsAll.filter(c => c.has_fab);
    },
    fabFilteredClients() {
      const q = (this.fabSearch || '').toLowerCase();
      return this.fabClientsAll().filter(c => !q || (c.name || '').toLowerCase().includes(q));
    },
    async pickFabClient(c) {
      this.fabClient = c;
      this.fabApplied = false;
      this.fabPicked = false;
      await this.loadClientFabbisogni(c.id);   // sets fabbisogniData (null if no fresh model)
      this.fabPicked = true;
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
        this.overwriteConfirmed = false;
        this.fabbisogniData = null;
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
window.substitutionPicker = substitutionPicker;
