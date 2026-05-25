// Importer dieta — Alpine component condiviso Excel + PDF.
// Una factory `createDietImporter(config)` produce l'oggetto Alpine; le due
// feature (Excel sync, PDF async con polling) la istanziano con config diversa.
// `dietImporter()` resta come wrapper retro-compatibile per il template Excel.

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
    // Mappatura phase backend → step index (solo async)
    phaseMap: null,
    // Minimo "perceived loading" (ms): rilevante solo in sync
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
    // Garantisci copy completo anche se override parziale
    config.copy = Object.assign({}, EXCEL_DEFAULTS.copy, (userConfig && userConfig.copy) || {});

    const base = {
      weekDays: WEEK_DAYS,
      // ─── Config (esposto al template per copy + flags) ────────────
      cfg: config,

      currentStep: 1,

      // Step 1
      file: null,
      dragOver: false,
      clientSearch: '',
      selectedClient: null,
      clientDropdownOpen: false,
      clientResults: [],
      planTitle: '',

      // Step 2
      phase: 0,
      steps: config.steps.slice(),
      motivationalMessages: config.motivationalMessages.slice(),
      motivationalMsg: '',
      motivationalTimer: null,
      phaseTimer: null,
      pollTimer: null,
      jobId: null,
      pollProgressPercent: 0,

      // Step 3
      diet: { days: [], supplements: [] },
      confidence: { fields_total: 0, fields_uncertain: 0, ratio: 0 },
      documentSummary: null,
      activeDay: null,
      saving: false,

      // Misc
      errorMsg: '',
      toast: '',
      toastTimer: null,
      csrf: '',

      init() {
        const meta = document.querySelector('meta[name="csrf-token"]');
        this.csrf = meta ? meta.content : '';
        this.searchClients();
      },

      get canSubmit() {
        return this.file && this.selectedClient && this.planTitle.trim().length > 0;
      },

      get filteredClients() {
        return this.clientResults;
      },

      formatSize(bytes) {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
        return (bytes / 1024 / 1024).toFixed(2) + ' MB';
      },

      // ─── Step 1 ───────────────────────────────
      async searchClients() {
        const q = this.clientSearch || '';
        try {
          const r = await fetch('/api/clients/search/?q=' + encodeURIComponent(q));
          if (r.ok) {
            this.clientResults = await r.json();
          }
        } catch (e) { console.error(e); }
      },

      pickClient(c) {
        this.selectedClient = c;
        this.clientSearch = c.name;
        this.clientDropdownOpen = false;
      },

      onFile(ev) {
        const f = ev.target.files && ev.target.files[0];
        if (!f) return;
        this.setFile(f);
      },

      onDrop(ev) {
        this.dragOver = false;
        const f = ev.dataTransfer && ev.dataTransfer.files && ev.dataTransfer.files[0];
        if (!f) return;
        this.setFile(f);
      },

      setFile(f) {
        const name = (f.name || '').toLowerCase();
        if (!this.cfg.extPattern.test(name)) {
          this.flashError(this.cfg.copy.formatError);
          return;
        }
        if (f.size > this.cfg.maxBytes) {
          this.flashError(this.cfg.copy.tooLargeError);
          return;
        }
        this.file = f;
      },

      clearFile() {
        this.file = null;
        if (this.$refs.fileInput) this.$refs.fileInput.value = '';
      },

      flashError(msg) {
        this.errorMsg = msg;
        this.currentStep = 'error';
      },

      // ─── Step 2: submit + loading anim ────────
      async submitFile() {
        if (!this.canSubmit) return;
        this.currentStep = 2;
        this.startLoadingAnim();

        const fd = new FormData();
        fd.append('file', this.file);
        fd.append('plan_title', this.planTitle);
        fd.append('client_id', this.selectedClient.id);

        if (this.cfg.async) {
          await this.submitAsync(fd);
        } else {
          await this.submitSync(fd);
        }
      },

      async submitSync(fd) {
        const minDelay = new Promise(res => setTimeout(res, this.cfg.minPerceivedMs));
        try {
          const [resp] = await Promise.all([
            fetch(this.cfg.submitUrl, {
              method: 'POST',
              headers: { 'X-CSRFToken': this.csrf },
              body: fd,
            }),
            minDelay,
          ]);
          this.stopLoadingAnim();
          if (!resp.ok && resp.status !== 206) {
            const err = await resp.json().catch(() => ({}));
            this.errorMsg = this.translateError(err);
            this.currentStep = 'error';
            return;
          }
          const data = await resp.json();
          this.applyExtractionResult(data);
        } catch (e) {
          this.stopLoadingAnim();
          this.errorMsg = 'Errore di rete: ' + (e.message || e);
          this.currentStep = 'error';
        }
      },

      async submitAsync(fd) {
        try {
          const startResp = await fetch(this.cfg.submitUrl, {
            method: 'POST',
            headers: { 'X-CSRFToken': this.csrf },
            body: fd,
          });
          if (!startResp.ok) {
            this.stopLoadingAnim();
            const err = await startResp.json().catch(() => ({}));
            this.errorMsg = this.translateError(err);
            this.currentStep = 'error';
            return;
          }
          const startData = await startResp.json();
          this.jobId = startData.job_id;
          if (!this.jobId) {
            this.stopLoadingAnim();
            this.errorMsg = 'Avvio elaborazione fallito (nessun job_id)';
            this.currentStep = 'error';
            return;
          }
          this.startPolling();
        } catch (e) {
          this.stopLoadingAnim();
          this.errorMsg = 'Errore di rete: ' + (e.message || e);
          this.currentStep = 'error';
        }
      },

      startPolling() {
        if (this.pollTimer) clearInterval(this.pollTimer);
        this.pollTimer = setInterval(() => this.pollOnce(), this.cfg.pollIntervalMs);
        this.pollOnce();
      },

      stopPolling() {
        if (this.pollTimer) { clearInterval(this.pollTimer); this.pollTimer = null; }
      },

      async pollOnce() {
        if (!this.jobId) return;
        try {
          const r = await fetch(this.cfg.statusUrl + '?job_id=' + encodeURIComponent(this.jobId));
          if (!r.ok) {
            this.stopPolling(); this.stopLoadingAnim();
            const err = await r.json().catch(() => ({}));
            this.errorMsg = this.translateError(err);
            this.currentStep = 'error';
            return;
          }
          const data = await r.json();
          this.pollProgressPercent = data.percent || 0;
          if (data.phase && this.cfg.phaseMap && this.cfg.phaseMap[data.phase] != null) {
            this.phase = this.cfg.phaseMap[data.phase];
          }
          if (data.status === 'done') {
            this.stopPolling(); this.stopLoadingAnim();
            this.applyExtractionResult(data.result || {});
          } else if (data.status === 'error') {
            this.stopPolling(); this.stopLoadingAnim();
            this.errorMsg = this.translateError({ error: data.error_code, detail: data.detail });
            this.currentStep = 'error';
          }
        } catch (e) {
          // soft fail: continua a polleggiare
          console.warn('poll error', e);
        }
      },

      applyExtractionResult(data) {
        this.diet = this.hydrateDiet(data.extracted || { days: [] });
        this.confidence = data.confidence || { fields_total: 0, fields_uncertain: 0, ratio: 0 };
        this.documentSummary = data.document_summary || (data.extracted && data.extracted.document_summary) || null;
        if (data.client) this.selectedClient = data.client;
        if (data.plan_title) this.planTitle = data.plan_title;
        this.activeDay = this.diet.days[0]?.day_of_week || null;
        this.currentStep = 3;
      },

      translateError(err) {
        if (!err) return 'Estrazione fallita.';
        const code = err.error;
        if (code === 'excel_invalid') return 'Il file Excel non è leggibile. Prova con un altro formato.';
        if (code === 'pdf_invalid') return 'Non siamo riusciti a leggere questo PDF. Prova con un file diverso.';
        if (code === 'pdf_no_content') return 'Il documento non sembra contenere una dieta riconoscibile.';
        if (code === 'ai_failed') return 'L\'analisi AI non è riuscita. Riprova tra poco.';
        if (code === 'job_not_found') return 'Sessione di elaborazione scaduta. Riprova.';
        if (code === 'unknown') return 'Errore inatteso durante l\'estrazione.';
        return err.detail || err.error || 'Estrazione fallita.';
      },

      startLoadingAnim() {
        this.phase = 0;
        let i = 0;
        this.motivationalMsg = this.motivationalMessages[0];
        // Avanzamento automatico fasi solo in modalità sync (in async lo guida il backend)
        if (!this.cfg.async) {
          this.phaseTimer = setInterval(() => {
            if (this.phase < this.steps.length - 1) this.phase++;
          }, 1500);
        }
        this.motivationalTimer = setInterval(() => {
          i = (i + 1) % this.motivationalMessages.length;
          this.motivationalMsg = this.motivationalMessages[i];
        }, 2000);
      },

      stopLoadingAnim() {
        if (this.phaseTimer) clearInterval(this.phaseTimer);
        if (this.motivationalTimer) clearInterval(this.motivationalTimer);
        this.phase = this.steps.length;
      },

      // ─── Step 3: revisione ────────────────────
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
          supplement_id: s.supplement_id || null,
          source_page: s.source_page ?? null,
          matched_name: s.matched_name || null,
          _candidates: s.candidates || [],
        }));
        return { ...raw, days, supplements };
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

      async searchFoodInline(food, query) {
        if (!query || query.length < 2) return;
        try {
          const r = await fetch('/api/nutrizione/alimenti/?q=' + encodeURIComponent(query));
          if (r.ok) {
            const data = await r.json();
            food._candidates = data.results || [];
          }
        } catch (e) { console.error(e); }
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
        if (!query || query.length < 2) return;
        try {
          const r = await fetch('/api/nutrizione/alimenti/?q=' + encodeURIComponent(query));
          if (r.ok) {
            const data = await r.json();
            sub._candidates = data.results || [];
          }
        } catch (e) { console.error(e); }
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

      // ─── Integratori ─────────────────────────
      async searchSupplementInline(supp, query) {
        if (!query || query.length < 2) return;
        try {
          const r = await fetch('/api/nutrizione/integratori/?q=' + encodeURIComponent(query));
          if (r.ok) {
            const data = await r.json();
            supp._candidates = data.results || [];
          }
        } catch (e) { console.error(e); }
      },
      pickSupplement(supp, candidate) {
        supp.supplement_id = candidate.id;
        supp.name = candidate.name;
        supp._candidates = [];
        supp.uncertain = false;
      },
      addSupplement() {
        if (!this.diet.supplements) this.diet.supplements = [];
        this.diet.supplements.push({
          name: '', dose: '', timing: '', notes: '',
          uncertain: true, supplement_id: null,
          source_page: null, _candidates: [],
        });
      },
      removeSupplement(idx) {
        this.diet.supplements.splice(idx, 1);
      },

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

      reset() {
        if (!confirm('Vuoi davvero ricominciare? Le modifiche andranno perse.')) return;
        this.stopPolling();
        this.currentStep = 1;
        this.file = null;
        this.jobId = null;
        this.diet = { days: [], supplements: [] };
        this.confidence = { fields_total: 0, fields_uncertain: 0, ratio: 0 };
        this.documentSummary = null;
      },

      async save() {
        this.saving = true;
        const payload = {
          plan_title: this.planTitle,
          client_id: this.selectedClient?.id || null,
          assign_now: true,
          diet_json: {
            diet_name: this.planTitle,
            extraction_notes: this.diet.extraction_notes || null,
            days: this.diet.days.map(d => ({
              day_of_week: d.day_of_week,
              notes: d.notes || null,
              meals: d.meals.map(m => ({
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
              supplement_id: s.supplement_id,
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
          this.flashToast('Dieta salvata con successo!');
          setTimeout(() => { window.location.href = '/nutrizione/piani/'; }, 1200);
        } catch (e) {
          this.saving = false;
          this.errorMsg = 'Errore di rete: ' + (e.message || e);
          this.currentStep = 'error';
        }
      },

      flashToast(msg) {
        this.toast = msg;
        if (this.toastTimer) clearTimeout(this.toastTimer);
        this.toastTimer = setTimeout(() => { this.toast = ''; }, 3000);
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
