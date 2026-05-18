// Importer dieta Excel — Alpine component
// Stato: 3 step (1=upload, 2=loading, 3=revisione) + 'error'

function dietImporter() {
  return {
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
    motivationalMsg: '',
    motivationalTimer: null,
    phaseTimer: null,

    // Step 3
    diet: { days: [] },
    confidence: { fields_total: 0, fields_uncertain: 0, ratio: 0 },
    activeDay: null,
    saving: false,

    // Misc
    errorMsg: '',
    toast: '',
    toastTimer: null,

    init() {
      // CSRF
      const meta = document.querySelector('meta[name="csrf-token"]');
      this.csrf = meta ? meta.content : '';
      // Default clients ricerca vuota
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
      } catch (e) {
        console.error(e);
      }
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
      if (!name.endsWith('.xlsx') && !name.endsWith('.xls')) {
        this.flashError('Formato non supportato (solo .xlsx/.xls)');
        return;
      }
      if (f.size > 10 * 1024 * 1024) {
        this.flashError('File troppo grande (max 10 MB)');
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

      // Min 2s di animazione percepita; ma min 4.5s per coprire le 3 fasi
      const minDelay = new Promise(res => setTimeout(res, 4500));

      try {
        const [resp] = await Promise.all([
          fetch('/api/nutrizione/import/excel/', {
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
        this.diet = this.hydrateDiet(data.extracted || { days: [] });
        this.confidence = data.confidence || { fields_total: 0, fields_uncertain: 0, ratio: 0 };
        if (data.client) this.selectedClient = data.client;
        if (data.plan_title) this.planTitle = data.plan_title;
        this.activeDay = this.diet.days[0]?.day_of_week || null;
        this.currentStep = 3;
      } catch (e) {
        this.stopLoadingAnim();
        this.errorMsg = 'Errore di rete: ' + (e.message || e);
        this.currentStep = 'error';
      }
    },

    translateError(err) {
      if (err.error === 'excel_invalid') return 'Il file Excel non è leggibile. Prova con un altro formato.';
      if (err.error === 'ai_failed') return 'L\'analisi AI non è riuscita. Riprova tra poco.';
      if (err.error === 'unknown') return 'Errore inatteso durante l\'estrazione.';
      return err.detail || err.error || 'Estrazione fallita.';
    },

    startLoadingAnim() {
      this.phase = 0;
      let i = 0;
      this.motivationalMsg = this.motivationalMessages[0];
      this.phaseTimer = setInterval(() => {
        if (this.phase < this.steps.length - 1) {
          this.phase++;
        }
      }, 1500);
      this.motivationalTimer = setInterval(() => {
        i = (i + 1) % this.motivationalMessages.length;
        this.motivationalMsg = this.motivationalMessages[i];
      }, 2000);
    },

    stopLoadingAnim() {
      if (this.phaseTimer) clearInterval(this.phaseTimer);
      if (this.motivationalTimer) clearInterval(this.motivationalTimer);
      this.phase = this.steps.length;  // tutti completati
    },

    // ─── Step 3: revisione ────────────────────
    hydrateDiet(raw) {
      // Garantisce campi UI (_candidates) anche se backend non li espone
      const days = (raw.days || []).map(d => ({
        ...d,
        meals: (d.meals || []).map(m => ({
          ...m,
          foods: (m.foods || []).map(f => ({
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
            _candidates: f.candidates || [],
            _foodCache: null,  // popolato a pickFood
          })),
        })),
      }));
      return { ...raw, days };
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
      food._foodCache = candidate;  // per macro on-the-fly
      food._candidates = [];
      food.uncertain = false;
    },

    addFood(day, meal_idx) {
      day.meals[meal_idx].foods.push({
        name: '', quantity: 100, unit: 'g',
        food_id: null, uncertain: true,
        _candidates: [], _foodCache: null,
      });
    },

    removeFood(day, meal_idx, food_idx) {
      day.meals[meal_idx].foods.splice(food_idx, 1);
    },

    // Macro calcolate live: se food_id presente + _foodCache → da DB,
    // altrimenti usa valori AI (per 100g).
    macro(food, key) {
      const qty = parseFloat(food.quantity) || 0;
      let per100 = null;
      if (food._foodCache) {
        const c = food._foodCache;
        per100 = { kcal: c.kcal, protein: c.protein, carb: c.carb, fat: c.fat };
      } else if (food.calories != null || food.protein_g != null) {
        // Valori dall'AI: assumiamo siano già per la quantità indicata
        const total = { kcal: food.calories, protein: food.protein_g, carb: food.carbs_g, fat: food.fat_g };
        return total[key] != null ? Math.round(total[key]) : '—';
      }
      if (!per100 || per100[key] == null) return '—';
      const unitFactor = (food.unit === 'g' || food.unit === 'ml') ? 1 : 100;  // pz/tbsp/tsp: tratto qty come "porzioni" → 1pz = 100g fallback
      return Math.round(per100[key] * qty * unitFactor / 100);
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
    get avgKcal() { return this.macroSum('kcal'); },
    get avgProt() { return this.macroSum('protein'); },
    get avgCarb() { return this.macroSum('carb'); },
    get avgFat()  { return this.macroSum('fat'); },

    reset() {
      if (!confirm('Vuoi davvero ricominciare? Le modifiche andranno perse.')) return;
      this.currentStep = 1;
      this.file = null;
      this.diet = { days: [] };
      this.confidence = { fields_total: 0, fields_uncertain: 0, ratio: 0 };
    },

    async save() {
      this.saving = true;
      // Sanitizza payload: rimuovi campi _* prima di mandare
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
              })),
            })),
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
        // Redirect dopo 1.2s
        setTimeout(() => {
          window.location.href = '/nutrizione/piani/';
        }, 1200);
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
  };
}
