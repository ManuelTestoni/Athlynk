// Importer dieta — Alpine component condiviso Excel + PDF.
// Costruito sopra createImportWizardCore (step machine, dropzone, polling),
// come workout_importer.js. Aggiunge: hydrateDiet, food search & match resolve
// (con filtro categorie del builder), sostituzioni, integratori, macro math,
// review MACRO (target per giorno/piano), save (confirm endpoint).

(function () {
  'use strict';

  // ─── Config default ────────────────────────────────────────────────
  const EXCEL_DEFAULTS = {
    sourceType: 'excel',
    accept: '.xlsx,.xls',
    extPattern: /\.(xlsx|xls)$/i,
    maxBytes: 10 * 1024 * 1024,
    submitUrl: '/api/nutrizione/import/excel/',
    statusUrl: null,
    async: false,
    pollIntervalMs: 1500,
    showSourceBadge: false,
    steps: [
      { icon: 'ph ph-file-xls', label: 'Lettura file Excel...' },
      { icon: 'ph ph-brain', label: 'Analisi AI in corso...' },
      { icon: 'ph ph-list-checks', label: 'Mappatura campi...' },
    ],
    motivationalMessages: [
      'Sto identificando i giorni della dieta...',
      'Sto riconoscendo gli alimenti...',
      'Sto normalizzando le unità di misura...',
      'Sto cercando i match nel database...',
    ],
    copy: {
      formatError: 'Formato non supportato (solo .xlsx/.xls)',
      tooLargeError: 'File troppo grande (max 10 MB)',
      invalidFileError: 'Il file non è leggibile. Prova con un altro formato.',
    },
    errorMap: {
      pdf_no_content: 'Il documento non sembra contenere una dieta riconoscibile.',
    },
    phaseMap: null,
    minPerceivedMs: 4500,
  };

  // ─── Day registry (per chart mixin condiviso) ─────────────────────
  const WEEK_DAYS = [
    { code: 'MONDAY',    label: 'Lun' },
    { code: 'TUESDAY',   label: 'Mar' },
    { code: 'WEDNESDAY', label: 'Mer' },
    { code: 'THURSDAY',  label: 'Gio' },
    { code: 'FRIDAY',    label: 'Ven' },
    { code: 'SATURDAY',  label: 'Sab' },
    { code: 'SUNDAY',    label: 'Dom' },
  ];

  // ─── Factory ───────────────────────────────────────────────────────
  function createDietImporter(userConfig) {
    const config = Object.assign({}, EXCEL_DEFAULTS, userConfig || {});
    config.copy = Object.assign({}, EXCEL_DEFAULTS.copy, (userConfig && userConfig.copy) || {});
    config.errorMap = Object.assign({}, EXCEL_DEFAULTS.errorMap, (userConfig && userConfig.errorMap) || {});

    const core = window.createImportWizardCore(config);

    const extension = {
      weekDays: WEEK_DAYS,

      // Plan shape, chosen on the review step. Drives which builder we hand the
      // saved plan to: FOOD/MACRO × DAILY/WEEKLY are four different editors.
      // Re-seeded from the extraction hints in applyExtractionResult().
      planKind: 'DAILY',
      planMode: 'FOOD',

      // Step 3
      diet: { days: [], supplements: [] },
      confidence: { fields_total: 0, fields_uncertain: 0, ratio: 0 },
      documentSummary: null,
      activeDay: null,

      // Food category filter (builder parity: api_food_search filter=cat&cat=ID)
      foodFilters: { cat: '' },
      foodCategories: [],

      init() {
        this._initCore();
        this._loadFoodCategories();
      },

      async _loadFoodCategories() {
        try {
          const r = await fetch('/api/nutrizione/alimenti/?q=&include_cats=1');
          if (r.ok) {
            const data = await r.json();
            this.foodCategories = data.categories || [];
          }
        } catch (e) { console.warn('food categories fetch fail', e); }
      },

      applyExtractionResult(data) {
        const extracted = data.extracted || { days: [] };
        this.diet = this.hydrateDiet(extracted);
        this.confidence = data.confidence || { fields_total: 0, fields_uncertain: 0, ratio: 0 };
        this.documentSummary = data.document_summary || extracted.document_summary || null;
        if (data.plan_title) this.planTitle = data.plan_title;
        // Seed the plan shape from the extraction/structure hints; the coach
        // can still override it on the review step.
        this.planMode = extracted.plan_mode === 'MACRO' ? 'MACRO' : 'FOOD';
        this.planKind = extracted.plan_kind
          || ((this.diet.days || []).length > 1 ? 'WEEKLY' : 'DAILY');
        if (this.planMode === 'MACRO' && this.planKind === 'WEEKLY') this.ensureMacroWeekDays();
        this.activeDay = this.diet.days[0]?.day_of_week || null;
        this.currentStep = 3;
      },

      // ─── Hydrate ──────────────────────────────
      hydrateDiet(raw) {
        const hydrateFood = (f) => ({
          name: f.name || '',
          quantity: f.quantity ?? 0,
          unit: f.unit || 'g',
          food_id: f.food_id || null,
          uncertain: !!f.uncertain,
          notes: f.notes || null,
          calories: f.calories,
          protein_g: f.protein_g,
          carbs_g: f.carbs_g,
          fat_g: f.fat_g,
          source_page: f.source_page ?? null,
          source_chunk: f.source_chunk ?? null,
          db_macros: f.db_macros || null,
          matched_name: f.matched_name || null,
          _candidates: f.candidates || [],
          _foodCache: null,
          subsOpen: false,
          addSubMode: null,
          substitutions: (f.substitutions || []).map(s => ({
            name: s.name || '',
            quantity: s.quantity ?? 0,
            unit: s.unit || 'g',
            mode: s.mode || 'ISOKCAL',
            food_id: s.food_id || null,
            uncertain: !!s.uncertain,
            notes: s.notes || null,
            source_page: s.source_page ?? null,
            db_macros: s.db_macros || null,
            matched_name: s.matched_name || null,
            _candidates: s.candidates || [],
            _foodCache: null,
          })),
        });
        const days = (raw.days || []).map(d => ({
          ...d,
          target_kcal: d.target_kcal ?? null,
          target_protein_g: d.target_protein_g ?? null,
          target_carb_g: d.target_carb_g ?? null,
          target_fat_g: d.target_fat_g ?? null,
          meals: (d.meals || []).map(m => ({
            ...m,
            foods: (m.foods || []).map(hydrateFood),
          })),
        }));
        const supplements = (raw.supplements || []).map(s => ({
          name: s.name || '',
          dose: s.dose || '',
          timing: s.timing || '',
          notes: s.notes || '',
          uncertain: !!s.uncertain,
          source_page: s.source_page ?? null,
        }));
        return {
          ...raw,
          days,
          supplements,
          daily_kcal: raw.daily_kcal ?? raw.total_calories_daily ?? null,
          protein_target_g: raw.protein_target_g ?? null,
          carb_target_g: raw.carb_target_g ?? null,
          fat_target_g: raw.fat_target_g ?? null,
        };
      },

      DAY_LABELS: {
        MONDAY: 'Lunedì', TUESDAY: 'Martedì', WEDNESDAY: 'Mercoledì',
        THURSDAY: 'Giovedì', FRIDAY: 'Venerdì', SATURDAY: 'Sabato', SUNDAY: 'Domenica',
      },
      MEAL_LABELS: {
        BREAKFAST: 'Colazione', MORNING_SNACK: 'Spuntino mattutino',
        LUNCH: 'Pranzo', AFTERNOON_SNACK: 'Spuntino pomeridiano', DINNER: 'Cena',
      },
      MEAL_ICONS: {
        BREAKFAST: 'ph ph-coffee', MORNING_SNACK: 'ph ph-apple-logo',
        LUNCH: 'ph ph-bowl-food', AFTERNOON_SNACK: 'ph ph-cookie', DINNER: 'ph ph-fork-knife',
      },

      dayLabel(d) { return this.DAY_LABELS[d] || d; },
      mealLabel(m) { return this.MEAL_LABELS[m] || m; },
      mealIcon(m) { return this.MEAL_ICONS[m] || 'ph ph-bowl-food'; },

      // ─── Food search & resolve ────────────────
      async _searchFoods(target, query) {
        const params = new URLSearchParams();
        params.set('q', query || '');
        if (this.foodFilters.cat) {
          params.set('filter', 'cat');
          params.set('cat', this.foodFilters.cat);
        }
        try {
          const r = await fetch('/api/nutrizione/alimenti/?' + params.toString());
          if (r.ok) {
            const data = await r.json();
            target._candidates = data.results || [];
          }
        } catch (e) { console.error(e); }
      },

      async searchFoodInline(food, query) {
        if ((!query || query.length < 2) && !this.foodFilters.cat) return;
        await this._searchFoods(food, query);
      },

      pickFood(food, candidate) {
        food.food_id = candidate.id;
        food.name = candidate.name;
        food._foodCache = candidate;
        food.db_macros = {
          kcal: candidate.kcal, protein: candidate.protein,
          carb: candidate.carb, fat: candidate.fat,
        };
        food._candidates = [];
        food.uncertain = false;
      },

      addFood(day, meal_idx) {
        day.meals[meal_idx].foods.push({
          name: '', quantity: 100, unit: 'g',
          food_id: null, uncertain: true,
          source_page: null, source_chunk: null,
          _candidates: [], _foodCache: null,
          db_macros: null,
          subsOpen: false, addSubMode: null,
          substitutions: [],
        });
      },

      removeFood(day, meal_idx, food_idx) {
        day.meals[meal_idx].foods.splice(food_idx, 1);
      },

      // ─── Sostituzioni ────────────────────────
      async searchSubInline(sub, query) {
        if ((!query || query.length < 2) && !this.foodFilters.cat) return;
        await this._searchFoods(sub, query);
      },
      pickSub(sub, candidate) {
        sub.food_id = candidate.id;
        sub.name = candidate.name;
        sub._foodCache = candidate;
        sub.db_macros = {
          kcal: candidate.kcal, protein: candidate.protein,
          carb: candidate.carb, fat: candidate.fat,
        };
        sub._candidates = [];
        sub.uncertain = false;
      },
      addSubstitution(food, mode) {
        food.substitutions.push({
          name: '', quantity: food.quantity || 100, unit: food.unit || 'g',
          mode: mode || 'ISOKCAL',
          food_id: null, uncertain: true,
          notes: null, source_page: null,
          db_macros: null,
          _candidates: [], _foodCache: null,
        });
        food.subsOpen = true;
      },
      removeSubstitution(food, sub_idx) {
        food.substitutions.splice(sub_idx, 1);
      },
      SUB_MODE_LABELS: { ISOKCAL: 'iso-kcal', ISOPROT: 'iso-prot', ISOCARB: 'iso-carb' },
      SUB_MODE_COLORS: { ISOKCAL: 'var(--al-bronze)', ISOPROT: 'var(--al-aegean)', ISOCARB: 'var(--al-warn)' },
      subModeLabel(m) { return this.SUB_MODE_LABELS[m] || m; },
      subModeColor(m) { return this.SUB_MODE_COLORS[m] || 'var(--al-ink-mute)'; },

      // ─── Integratori (free-text) ─────────────────────────
      addSupplement() {
        if (!this.diet.supplements) this.diet.supplements = [];
        this.diet.supplements.push({
          name: '', dose: '', timing: '', notes: '',
          uncertain: false, source_page: null,
        });
      },
      async removeSupplement(idx) {
        const s = this.diet.supplements[idx];
        const label = (s && s.name || '').trim() || 'questo integratore';
        const ok = window.alConfirm ? await window.alConfirm({
          icon: 'ph-trash', title: 'Eliminare\nl\'integratore?',
          subtitle: '«' + label + '» verrà rimosso.', confirmLabel: 'Sì, elimina',
        }) : confirm('Eliminare «' + label + '»?');
        if (ok) this.diet.supplements.splice(idx, 1);
      },

      // ─── MACRO review (target per giorno / piano) ─────────
      ensureMacroWeekDays() {
        // Scaffold all 7 day rows for a MACRO-WEEKLY plan, seeding missing
        // days from the plan-level targets so the coach edits, not re-types.
        const byCode = {};
        for (const d of this.diet.days || []) byCode[d.day_of_week] = d;
        this.diet.days = WEEK_DAYS.map(w => byCode[w.code] || {
          day_of_week: w.code,
          meals: [],
          target_kcal: this.diet.daily_kcal ?? null,
          target_protein_g: this.diet.protein_target_g ?? null,
          target_carb_g: this.diet.carb_target_g ?? null,
          target_fat_g: this.diet.fat_target_g ?? null,
        });
      },

      onPlanShapeChange() {
        if (this.planMode === 'MACRO' && this.planKind === 'WEEKLY') this.ensureMacroWeekDays();
      },

      // Sanity check 4/4/9: kcal dichiarate vs derivate dai macro (±10%).
      macroKcalDelta(kcal, p, c, f) {
        const declared = parseFloat(kcal);
        const derived = (parseFloat(p) || 0) * 4 + (parseFloat(c) || 0) * 4 + (parseFloat(f) || 0) * 9;
        if (!declared || !derived) return null;
        return Math.round(declared - derived);
      },
      macroKcalWarn(kcal, p, c, f) {
        const delta = this.macroKcalDelta(kcal, p, c, f);
        if (delta === null) return false;
        const declared = parseFloat(kcal) || 1;
        return Math.abs(delta) / declared > 0.10;
      },

      // ─── Macro math (FOOD mode) ──────────────
      macro(food, key) {
        const qty = parseFloat(food.quantity) || 0;
        // Priorità sorgenti macro:
        //   1. _foodCache: utente ha selezionato un candidato dal DB → DB authoritative
        //   2. db_macros: backend ha auto-matchato l'alimento nel DB → DB authoritative
        //   3. Valori AI: fallback se nessun match DB
        const unitFactor = (food.unit === 'g' || food.unit === 'ml') ? 1 : 100;
        const computeFromPer100 = (per100) => {
          if (per100[key] == null) return null;
          return Math.round(per100[key] * qty * unitFactor / 100);
        };
        if (food._foodCache) {
          const c = food._foodCache;
          const v = computeFromPer100({ kcal: c.kcal, protein: c.protein, carb: c.carb, fat: c.fat });
          if (v != null) return v;
        }
        if (food.db_macros) {
          const v = computeFromPer100(food.db_macros);
          if (v != null) return v;
        }
        const aiKey = { kcal: 'calories', protein: 'protein_g', carb: 'carbs_g', fat: 'fat_g' }[key];
        if (aiKey && food[aiKey] != null) {
          return Math.round(food[aiKey]);
        }
        return '—';
      },

      macroSum(key) {
        let total = 0;
        for (const day of this.diet.days) {
          let dayTotal = 0;
          for (const meal of day.meals) {
            for (const food of meal.foods) {
              const v = this.macro(food, key);
              if (typeof v === 'number') dayTotal += v;
            }
          }
          total += dayTotal;
        }
        const n = this.diet.days.length || 1;
        return Math.round(total / n);
      },
      mealKcal(meal) {
        let total = 0;
        for (const food of meal.foods || []) {
          const v = this.macro(food, 'kcal');
          if (typeof v === 'number') total += v;
        }
        return total;
      },
      get avgKcal() { return this.macroSum('kcal'); },
      get avgProt() { return this.macroSum('protein'); },
      get avgCarb() { return this.macroSum('carb'); },
      get avgFat()  { return this.macroSum('fat'); },

      async reset() {
        if (!await window.alConfirm({ variant: 'neutral', icon: 'ph-arrow-counter-clockwise', title: 'Ricominciare\nda capo?', subtitle: 'Tutte le modifiche andranno perse.', confirmLabel: 'Sì, ricomincia' })) return;
        this.stopPolling();
        this.stopLoadingAnim();
        this.currentStep = 1;
        this.file = null;
        this.jobId = null;
        this.pendingResult = null;
        this.targetPhase = 0;
        this.displayedPhase = 0;
        this.phaseEnteredAt = [];
        this.diet = { days: [], supplements: [] };
        this.confidence = { fields_total: 0, fields_uncertain: 0, ratio: 0 };
        this.documentSummary = null;
      },

      // ─── Save (confirm) ─────────────────────
      async save() {
        this.saving = true;
        const isMacro = this.planMode === 'MACRO';
        const payload = {
          plan_title: this.planTitle,
          // Decides which builder receives the plan. Import never assigns to
          // an athlete: assignment lives in the builder we hand off to.
          plan_kind: this.planKind,
          plan_mode: this.planMode,
          diet_json: {
            diet_name: this.planTitle,
            extraction_notes: this.diet.extraction_notes || null,
            daily_kcal: this.diet.daily_kcal || null,
            protein_target_g: this.diet.protein_target_g || null,
            carb_target_g: this.diet.carb_target_g || null,
            fat_target_g: this.diet.fat_target_g || null,
            days: this.diet.days.map(d => ({
              day_of_week: d.day_of_week,
              notes: d.notes || null,
              target_kcal: d.target_kcal || null,
              target_protein_g: d.target_protein_g || null,
              target_carb_g: d.target_carb_g || null,
              target_fat_g: d.target_fat_g || null,
              meals: isMacro ? [] : d.meals.map(m => ({
                meal_type: m.meal_type,
                notes: m.notes || null,
                foods: m.foods.map(f => ({
                  name: f.name,
                  quantity: f.quantity,
                  unit: f.unit,
                  food_id: f.food_id,
                  uncertain: f.uncertain,
                  notes: f.notes,
                  substitutions: (f.substitutions || []).map(s => ({
                    name: s.name,
                    quantity: s.quantity,
                    unit: s.unit,
                    mode: s.mode || 'ISOKCAL',
                    food_id: s.food_id,
                    uncertain: s.uncertain,
                    notes: s.notes,
                  })),
                })),
              })),
            })),
            supplements: (this.diet.supplements || []).map(s => ({
              name: s.name,
              dose: s.dose || null,
              timing: s.timing || null,
              notes: s.notes || null,
              uncertain: s.uncertain,
            })),
          },
        };
        try {
          const r = await fetch('/api/nutrizione/import/conferma/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this.csrf },
            body: JSON.stringify(payload),
          });
          const data = await r.json().catch(() => ({}));
          this.saving = false;
          if (!r.ok) {
            this.errorMsg = data.detail || data.error || 'Salvataggio fallito';
            this.currentStep = 'error';
            return;
          }
          this.flashToast('Dieta importata. Apro il builder…');
          setTimeout(() => { window.location.href = data.redirect_url || '/nutrizione/piani/'; }, 900);
        } catch (e) {
          this.saving = false;
          this.errorMsg = 'Errore di rete: ' + (e.message || e);
          this.currentStep = 'error';
        }
      },

      // ─── Chart adapters (per nutrition_wizard_charts mixin) ─────────
      _findDay(code) {
        return (this.diet.days || []).find(d => d.day_of_week === code) || null;
      },
      _foodMacro(food, key) {
        const v = this.macro(food, key);
        return typeof v === 'number' ? v : 0;
      },
      dayKcal(code) {
        const day = this._findDay(code);
        if (!day) return 0;
        let total = 0;
        for (const meal of day.meals || []) {
          for (const f of meal.foods || []) total += this._foodMacro(f, 'kcal');
        }
        return Math.round(total);
      },
      dayMacro(code, key) {
        const day = this._findDay(code);
        if (!day) return 0;
        let total = 0;
        for (const meal of day.meals || []) {
          for (const f of meal.foods || []) total += this._foodMacro(f, key);
        }
        return Math.round(total);
      },
      dayMealCount(code) {
        const day = this._findDay(code);
        return day ? (day.meals || []).length : 0;
      },
      hasAnyDay() { return (this.diet.days || []).some(d => (d.meals || []).length > 0); },
      hasAnyMealWithItem() {
        for (const d of this.diet.days || []) {
          for (const m of d.meals || []) {
            if ((m.foods || []).length) return true;
          }
        }
        return false;
      },
      filledDaysCount() {
        return (this.diet.days || []).filter(d => (d.meals || []).some(m => (m.foods || []).length)).length;
      },
      totalMacro(key) {
        // media giornaliera per piano settimanale (≥2 giorni); somma per giornaliero
        const days = this.diet.days || [];
        if (!days.length) return 0;
        let sum = 0;
        for (const d of days) sum += this.dayMacro(d.day_of_week, key);
        return days.length > 1 ? Math.round(sum / days.length) : Math.round(sum);
      },
      sidePanelMacro(key) { return this.totalMacro(key); },
      weekDayLabel(code) {
        const d = (this.weekDays || []).find(x => x.code === code);
        return d ? d.label : code;
      },
    };

    const base = Object.assign(core, extension);
    // Mix-in grafici (donut + histogram). Disponibile solo se script caricato.
    if (typeof window.nutritionWizardChartsMixin === 'function') {
      Object.assign(base, window.nutritionWizardChartsMixin());
    }
    return base;
  }

  // Wrapper retro-compatibile per il template Excel esistente
  function dietImporter() {
    return createDietImporter({});  // usa EXCEL_DEFAULTS
  }

  // Espone in window per Alpine
  window.createDietImporter = createDietImporter;
  window.dietImporter = dietImporter;
})();
