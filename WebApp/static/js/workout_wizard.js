document.addEventListener('alpine:init', () => {
  Alpine.data('workoutWizard', () => ({
    // ---- State ----
    plan: null,
    step: 1,
    activeDayIndex: 0,
    editingDayIdx: null,
    selectedExIds: [],
    flashIds: [],
    mobileTab: 'lib',
    analyticsOpen: false,

    library: { query: '', muscle: '', equipment: '', sport: '', items: [], loading: false },
    filters: { muscles: [], equipment: [], sports: [] },

    saveState: 'idle',
    saveTimer: null,
    saveInFlight: false,
    saveQueued: false,
    lastSavedAt: null,
    idleTimer: null,

    finalAction: null,
    clientQuery: '',
    clientsList: [],
    selectedClientIds: [],
    assignWeeks: null,
    finalizing: false,

    errors: { step1: '', step2: '', assign: '', finalize: '' },
    toast: '',

    urls: window.WIZARD_URLS,

    // ---- Progression state ----
    progression: { weeks: [], rules: [], overrides: [], computed: {}, conflicts: [] },
    progUi: {
      activeWeek: 1,
      activeExercise: null,
      drawerOpen: false,
      drawerMode: 'list',
      openDays: {},
      draftRule: null,
      previewComputed: {},
      previewTimer: null,
      chartMetric: 'volume', // volume | tonnage | intensity
    },
    draftRule: null,

    FAMILY_DEFS: [
      { value: 'LOAD', label: 'Carico' },
      { value: 'VOLUME', label: 'Volume' },
      { value: 'INTENSITY', label: 'Intensità' },
      { value: 'DENSITY', label: 'Densità' },
      { value: 'TEMPO', label: 'Tempo' },
      { value: 'ROM', label: 'ROM' },
      { value: 'VARIANT', label: 'Variante' },
      { value: 'FREQUENCY', label: 'Frequenza' },
      { value: 'UNDULATION', label: 'Ondulazione' },
      { value: 'DELOAD', label: 'Deload' },
      { value: 'VELOCITY', label: 'Velocità' },
    ],
    // Families hidden from the picker dropdown (legacy rules still render label-wise).
    HIDDEN_FAMILIES: ['TEMPO', 'ROM', 'VARIANT', 'FREQUENCY', 'VELOCITY'],
    // Subtypes hidden from the picker (legacy rules still render label-wise).
    HIDDEN_SUBTYPES: ['UND_DUP'],
    SUBTYPE_MAP: {
      LOAD: [
        { value: 'LOAD_LINEAR', label: 'Lineare (es. +2.5 kg/sett.)', metric: 'load', mode: 'FIXED_INCREMENT' },
        { value: 'LOAD_PERCENT', label: 'Percentuale (es. +2%)', metric: 'load', mode: 'PERCENT_INCREMENT' },
        { value: 'LOAD_MICRO', label: 'Micro-load (incrementi piccoli)', metric: 'load', mode: 'FIXED_INCREMENT' },
        { value: 'LOAD_MANUAL', label: 'Manuale per settimana', metric: 'load', mode: 'EXPLICIT_VALUES' },
      ],
      VOLUME: [
        { value: 'VOL_SETS', label: 'Aumento serie', metric: 'sets', mode: 'FIXED_INCREMENT' },
        { value: 'VOL_REPS', label: 'Aumento ripetizioni', metric: 'reps', mode: 'FIXED_INCREMENT' },
        { value: 'VOL_DOUBLE', label: 'Double progression', metric: 'reps', mode: 'RULE_BASED' },
      ],
      INTENSITY: [
        { value: 'INT_RPE', label: 'RPE progressivo', metric: 'rpe', mode: 'EXPLICIT_VALUES' },
        { value: 'INT_RIR', label: 'RIR progressivo', metric: 'rir', mode: 'EXPLICIT_VALUES' },
        { value: 'INT_PCT1RM', label: '% 1RM per settimana', metric: 'load', mode: 'EXPLICIT_VALUES' },
      ],
      DENSITY: [
        { value: 'DEN_REST', label: 'Riduzione recupero', metric: 'rest', mode: 'FIXED_INCREMENT' },
      ],
      TEMPO: [
        { value: 'TEMPO_PRESET', label: 'Preset tempo per settimana', metric: 'tempo', mode: 'EXPLICIT_VALUES' },
      ],
      ROM: [
        { value: 'ROM_INCREASE', label: 'Aumento ROM (stadi)', metric: 'rom', mode: 'RULE_BASED' },
      ],
      VARIANT: [
        { value: 'VAR_TRANSITION', label: 'Transizione variante', metric: 'exercise_variant', mode: 'EXPLICIT_VALUES' },
      ],
      FREQUENCY: [
        { value: 'FREQ_ADD', label: 'Aggiunta frequenza', metric: 'frequency', mode: 'MILESTONE_BASED' },
      ],
      UNDULATION: [
        { value: 'UND_WUP', label: 'WUP — Ondulata settimanale', metric: 'rep_range', mode: 'EXPLICIT_VALUES' },
        { value: 'UND_DUP', label: 'DUP — Ondulata giornaliera', metric: 'rep_range', mode: 'EXPLICIT_VALUES' },
      ],
      DELOAD: [
        { value: 'DEL_AUTO', label: 'Deload automatico (settimane periodiche)', metric: 'load', mode: 'RULE_BASED' },
      ],
      VELOCITY: [
        { value: 'VEL_TARGET', label: 'Target velocità', metric: 'velocity', mode: 'EXPLICIT_VALUES' },
      ],
    },
    WEEK_TYPES: [
      { value: 'STANDARD', label: 'Standard' },
      { value: 'DELOAD', label: 'Deload' },
      { value: 'TEST', label: 'Test' },
      { value: 'TECHNIQUE', label: 'Tecnica' },
      { value: 'RECOVERY', label: 'Recovery' },
    ],

    // ---- Init ----
    init() {
      const init = window.WIZARD_INIT || {};
      this.plan = {
        id: init.id || null,
        title: init.title || '',
        description: init.description || '',
        goal: init.goal || '',
        level: init.level || '',
        frequency_per_week: init.frequency_per_week || null,
        duration_weeks: init.duration_weeks || 8,
        status: init.status || 'DRAFT',
        last_step: init.last_step || 1,
        days: this._materializeDays(init.days || []),
      };

      // Resume to last_step if existing draft
      if (this.plan.id && this.plan.last_step) {
        this.step = Math.max(1, Math.min(4, this.plan.last_step));
        if (this.step === 3 && !this.hasProgressionStep()) this.step = 4;
      } else {
        this.step = 1;
      }

      // Hydrate progression state from server payload.
      this._hydrateProgression(init.progression || {});
      this.activeDayIndex = this.plan.days.length > 0 ? 0 : null;

      // Load filters + library on step 2
      this.loadFilters();
      this.loadLibrary();

      // Beforeunload save
      window.addEventListener('beforeunload', (e) => this._beforeUnload(e));

      // Idle timer
      this._resetIdleTimer();
      ['mousemove', 'keydown', 'click'].forEach(evt =>
        document.addEventListener(evt, () => this._resetIdleTimer(), { passive: true })
      );
    },

    _materializeDays(srvDays) {
      return srvDays.map((d, i) => ({
        local_id: d.local_id || `day-${Date.now()}-${i}`,
        pk: d.pk || null,
        order: d.order || i + 1,
        name: d.name || `Giorno ${i + 1}`,
        exercises: (d.exercises || []).map((ex, ei) => ({
          local_id: ex.local_id || `ex-${Date.now()}-${i}-${ei}`,
          pk: ex.pk || null,
          exercise_id: ex.exercise_id,
          exercise_name: ex.exercise_name,
          target_muscle_group: ex.target_muscle_group || '',
          primary_muscle: ex.primary_muscle || '',
          secondary_muscle: ex.secondary_muscle || '',
          equipment: ex.equipment || '',
          sets: ex.sets ?? 3,
          reps: ex.reps ?? '10',
          load_value: ex.load_value ?? null,
          load_unit: ex.load_unit || 'KG',
          recovery_seconds: ex.recovery_seconds ?? 90,
          notes: ex.notes || '',
          superset_group_id: ex.superset_group_id ?? null,
        })),
      }));
    },

    // ---- CSRF helper ----
    getCsrf() {
      return document.cookie.split('; ').find(r => r.startsWith('csrftoken='))?.split('=')[1] || '';
    },

    // ---- Step navigation ----
    stepName(s) { return ({1:'Informazioni', 2:'Builder', 3:'Progressione', 4:'Riepilogo & Assegna'})[s]; },

    hasProgressionStep() {
      return (this.plan?.duration_weeks || 0) > 1;
    },
    visibleSteps() {
      return this.hasProgressionStep() ? [1,2,3,4] : [1,2,4];
    },
    lastVisibleStep() {
      const v = this.visibleSteps();
      return v[v.length - 1];
    },

    canAdvanceStep1() {
      return this.plan && this.plan.title.trim().length > 0 && !!this.plan.frequency_per_week && !!this.plan.duration_weeks;
    },

    canAdvanceStep2() {
      return this.plan.days.some(d => d.exercises.length > 0);
    },

    goNext() {
      if (this.step === 1) {
        if (!this.canAdvanceStep1()) {
          this.errors.step1 = 'Compila titolo e numero allenamenti per settimana.';
          return;
        }
        this.errors.step1 = '';
        this._ensureDays();
        this.step = 2;
        this.plan.last_step = 2;
        this.$nextTick(() => this.bindSortable());
        this.saveDraft();
        return;
      }
      if (this.step === 2) {
        if (!this.canAdvanceStep2()) {
          this.errors.step2 = 'Aggiungi almeno un esercizio in almeno un giorno.';
          return;
        }
        this.errors.step2 = '';
        this.step = this.hasProgressionStep() ? 3 : 4;
        this.plan.last_step = this.step;
        this.saveDraft();
        return;
      }
      if (this.step === 3) {
        this.step = 4;
        this.plan.last_step = 4;
        this.saveDraft();
        return;
      }
    },

    goPrev() {
      if (this.step === 4) {
        this.step = this.hasProgressionStep() ? 3 : 2;
      } else if (this.step === 3) {
        this.step = 2;
      } else if (this.step > 1) {
        this.step -= 1;
      }
      if (this.step === 2) this.$nextTick(() => this.bindSortable());
    },

    setFrequency(n) {
      this.plan.frequency_per_week = n;
      this.markDirty();
    },

    _ensureDays() {
      const target = this.plan.frequency_per_week;
      // if days already have content matching, keep
      if (this.plan.days.length === target) return;

      if (this.plan.days.length < target) {
        for (let i = this.plan.days.length; i < target; i++) {
          this.plan.days.push({
            local_id: `day-${Date.now()}-${i}`,
            pk: null,
            order: i + 1,
            name: `Giorno ${i + 1}`,
            exercises: [],
          });
        }
      } else {
        // never exceed; trim only if user is truly reducing (unlikely after step 1 lock)
        this.plan.days = this.plan.days.slice(0, target);
      }
      if (this.activeDayIndex === null || this.activeDayIndex >= this.plan.days.length) {
        this.activeDayIndex = 0;
      }
    },

    activeDay() {
      if (this.activeDayIndex === null) return null;
      return this.plan.days[this.activeDayIndex] || null;
    },

    // ---- Library ----
    async loadFilters() {
      try {
        const r = await fetch(this.urls.filters);
        const d = await r.json();
        this.filters = d;
      } catch (e) { /* silent */ }
    },

    async loadLibrary() {
      this.library.loading = true;
      const params = new URLSearchParams();
      if (this.library.query) params.set('q', this.library.query);
      if (this.library.muscle) params.set('muscle', this.library.muscle);
      if (this.library.equipment) params.set('equipment', this.library.equipment);
      if (this.library.sport) params.set('sport', this.library.sport);
      try {
        const r = await fetch(`${this.urls.search_exercises}?${params.toString()}`);
        this.library.items = await r.json();
      } catch (e) {
        this.library.items = [];
      } finally {
        this.library.loading = false;
      }
    },

    openLibraryFocus() {
      this.mobileTab = 'lib';
      const inp = document.querySelector('aside input[type=text]');
      if (inp) inp.focus();
    },

    // ---- Add / remove exercises ----
    addExerciseToActiveDay(libEx) {
      if (this.activeDayIndex === null) {
        this.activeDayIndex = 0;
      }
      const day = this.activeDay();
      if (!day) return;
      day.exercises.push({
        local_id: `ex-${Date.now()}-${Math.random().toString(36).slice(2,7)}`,
        pk: null,
        exercise_id: libEx.id,
        exercise_name: libEx.name,
        target_muscle_group: libEx.target_muscle_group || '',
        primary_muscle: libEx.primary_muscle || '',
        secondary_muscle: libEx.secondary_muscle || '',
        equipment: libEx.equipment || '',
        sets: 3,
        reps: '10',
        load_value: null,
        load_unit: 'KG',
        recovery_seconds: 90,
        notes: '',
        superset_group_id: null,
      });
      this.flashIds.push(libEx.id);
      setTimeout(() => {
        this.flashIds = this.flashIds.filter(x => x !== libEx.id);
      }, 600);
      this.markDirty();
      this.$nextTick(() => this.bindSortable());
    },

    removeExercise(idx) {
      const day = this.activeDay();
      if (!day) return;
      day.exercises.splice(idx, 1);
      this.markDirty();
    },

    // ---- Superset ----
    toggleSelect(localId) {
      const i = this.selectedExIds.indexOf(localId);
      if (i >= 0) this.selectedExIds.splice(i, 1);
      else this.selectedExIds.push(localId);
    },

    createSuperset() {
      const day = this.activeDay();
      if (!day) return;
      // Determine next superset group id (max in this day + 1, fallback 1)
      const existing = day.exercises.map(e => e.superset_group_id).filter(x => x);
      const nextId = existing.length ? Math.max(...existing) + 1 : 1;
      day.exercises.forEach(ex => {
        if (this.selectedExIds.includes(ex.local_id)) {
          ex.superset_group_id = nextId;
        }
      });
      this.selectedExIds = [];
      this.markDirty();
    },

    // ---- Day rename ----
    startEditDay(i) { this.editingDayIdx = i; },
    finishEditDay() { this.editingDayIdx = null; this.markDirty(); },

    // ---- Drag & drop ----
    bindSortable() {
      if (typeof Sortable === 'undefined') return;
      const day = this.activeDay();
      if (!day) return;
      const list = document.getElementById('day-list-' + day.local_id);
      if (!list || list._sortableBound) return;
      list._sortableBound = true;
      const self = this;
      Sortable.create(list, {
        handle: '.drag-handle',
        animation: 150,
        draggable: '.wiz-ex-row',
        onEnd(evt) {
          if (evt.oldIndex === evt.newIndex) return;
          const arr = day.exercises;
          const [moved] = arr.splice(evt.oldIndex, 1);
          arr.splice(evt.newIndex, 0, moved);
          self.markDirty();
        },
      });
    },

    // ---- Analytics calculations ----
    totalExercises() {
      return this.plan.days.reduce((sum, d) => sum + d.exercises.length, 0);
    },

    totalSets() {
      return this.plan.days.reduce((sum, d) =>
        sum + d.exercises.reduce((a, ex) => a + (parseInt(ex.sets) || 0), 0), 0);
    },

    estimatedDurationMin() {
      // sum of (sets * recovery + 60s buffer) per exercise / 60
      let secs = 0;
      this.plan.days.forEach(d => {
        d.exercises.forEach(ex => {
          const s = parseInt(ex.sets) || 0;
          const r = parseInt(ex.recovery_seconds) || 0;
          secs += s * r + 60;
        });
      });
      return Math.round(secs / 60);
    },

    volumeByMuscle() {
      const map = {};
      this.plan.days.forEach(d => {
        d.exercises.forEach(ex => {
          const reps = this._parseReps(ex.reps);
          const sets = parseInt(ex.sets) || 0;
          const baseVol = sets * reps;
          const primary = ex.target_muscle_group || ex.primary_muscle;
          const secondary = ex.secondary_muscle;
          if (primary) map[primary] = (map[primary] || 0) + baseVol;
          if (secondary) map[secondary] = (map[secondary] || 0) + baseVol * 0.5;
        });
      });
      const arr = Object.entries(map).map(([group, value]) => ({ group, value }));
      arr.sort((a, b) => b.value - a.value);
      const max = arr.length ? arr[0].value : 1;
      arr.forEach(r => r.pct = max ? Math.round((r.value / max) * 100) : 0);
      return arr;
    },

    _parseReps(reps) {
      if (typeof reps === 'number') return reps;
      const s = String(reps || '').trim();
      const m = s.match(/(\d+)(?:\s*[-–]\s*(\d+))?/);
      if (!m) return 10;
      if (m[2]) return Math.round((parseInt(m[1]) + parseInt(m[2])) / 2);
      return parseInt(m[1]) || 10;
    },

    // ---- Per-week progression analytics ----
    weekStats(week) {
      let sets = 0, volume = 0, tonnage = 0, intensitySum = 0, intensityN = 0, exCount = 0;
      this.plan.days.forEach(d => {
        d.exercises.forEach(ex => {
          exCount += 1;
          const c = (ex.pk && this.progression.computed?.[String(ex.pk)]?.[String(week)]) || {};
          const s = parseInt(c.set_count ?? ex.sets) || 0;
          const reps = this._parseReps(c.rep_range ?? ex.reps);
          const unit = c.load_unit || ex.load_unit;
          const loadRaw = c.load_value ?? ex.load_value;
          const load = (unit === 'KG' && loadRaw !== null && loadRaw !== undefined && loadRaw !== '') ? parseFloat(loadRaw) : null;
          const rpe = c.rpe ?? ex.rpe;
          sets += s;
          volume += s * reps;
          if (load !== null && !isNaN(load)) tonnage += s * reps * load;
          if (rpe) { intensitySum += parseFloat(rpe); intensityN += 1; }
        });
      });
      return {
        sets,
        volume,
        tonnage: Math.round(tonnage),
        avg_rpe: intensityN ? +(intensitySum / intensityN).toFixed(1) : 0,
        exercises: exCount,
      };
    },

    weekStatsAll() {
      return this.weekNumbers().map(w => ({ week: w, ...this.weekStats(w) }));
    },

    chartMaxFor(metric) {
      const all = this.weekStatsAll();
      const key = metric === 'tonnage' ? 'tonnage' : metric === 'intensity' ? 'avg_rpe' : 'volume';
      const max = Math.max(0, ...all.map(s => s[key] || 0));
      return max || 1;
    },

    chartBarPct(metric, week) {
      const max = this.chartMaxFor(metric);
      const s = this.weekStats(week);
      const key = metric === 'tonnage' ? 'tonnage' : metric === 'intensity' ? 'avg_rpe' : 'volume';
      const v = s[key] || 0;
      return max ? Math.round((v / max) * 100) : 0;
    },

    chartLabelFor(metric, week) {
      const s = this.weekStats(week);
      if (metric === 'tonnage') return s.tonnage ? `${s.tonnage} kg` : '—';
      if (metric === 'intensity') return s.avg_rpe ? `${s.avg_rpe}` : '—';
      return s.volume ? String(s.volume) : '—';
    },

    // ---- Save / autosave ----
    markDirty() {
      this.saveState = 'idle';
      if (this.saveTimer) clearTimeout(this.saveTimer);
      this.saveTimer = setTimeout(() => this.saveDraft(), 1500);
    },

    async saveDraft(showToast = false) {
      if (this.saveInFlight) {
        this.saveQueued = true;
        return;
      }
      this.saveInFlight = true;
      this.saveState = 'saving';

      const url = this.plan.id
        ? this.urls.save.replace('__ID__', this.plan.id)
        : this.urls.save_new;

      const payload = this._serializePlan();

      try {
        const r = await fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this.getCsrf() },
          body: JSON.stringify(payload),
        });
        const d = await r.json();
        if (r.ok && d.plan) {
          this._mergeServerIds(d.plan);
          this.lastSavedAt = new Date();
          this.saveState = 'idle';
          if (showToast) this._showToast('Bozza salvata');
        } else {
          this.saveState = 'error';
        }
      } catch (e) {
        this.saveState = 'error';
      } finally {
        this.saveInFlight = false;
        if (this.saveQueued) {
          this.saveQueued = false;
          this.$nextTick(() => this.saveDraft());
        }
      }
    },

    _serializePlan() {
      return {
        title: this.plan.title,
        description: this.plan.description,
        goal: this.plan.goal,
        level: this.plan.level,
        frequency_per_week: this.plan.frequency_per_week,
        duration_weeks: this.plan.duration_weeks,
        last_step: this.step,
        days: this.plan.days.map((d, di) => ({
          pk: d.pk,
          local_id: d.local_id,
          order: di + 1,
          name: d.name,
          exercises: d.exercises.map((ex, ei) => ({
            pk: ex.pk,
            local_id: ex.local_id,
            exercise_id: ex.exercise_id,
            order: ei + 1,
            sets: ex.sets,
            reps: ex.reps,
            load_value: ex.load_value,
            load_unit: ex.load_unit,
            recovery_seconds: ex.recovery_seconds,
            notes: ex.notes,
            superset_group_id: ex.superset_group_id,
          })),
        })),
        progression: {
          weeks: this.progression.weeks.map(w => ({
            id: w.id || null,
            week_number: w.week_number,
            label: w.label || '',
            week_type: w.week_type || 'STANDARD',
            preset: w.preset || '',
            notes: w.notes || '',
          })),
          rules: this.progression.rules.map(r => ({
            id: typeof r.id === 'number' ? r.id : null,
            workout_exercise_id: r.workout_exercise_id,
            workout_exercise_local_id: r._exercise_local_id || null,
            order_index: r.order_index || 0,
            family: r.family,
            subtype: r.subtype,
            target_metric: r.target_metric,
            application_mode: r.application_mode || 'FIXED_INCREMENT',
            start_week: r.start_week || 1,
            end_week: r.end_week || null,
            parameters: r.parameters || {},
            stackable: r.stackable !== false,
            conflict_strategy: r.conflict_strategy || 'LAST_WINS',
            label: r.label || '',
          })),
          overrides: this.progression.overrides.map(o => ({
            id: typeof o.id === 'number' ? o.id : null,
            workout_exercise_id: o.workout_exercise_id,
            workout_exercise_local_id: o._exercise_local_id || null,
            week_number: o.week_number,
            metric: o.metric,
            value_json: o.value_json,
          })),
        },
      };
    },

    _mergeServerIds(srvPlan) {
      // Soft-merge: only fill missing PKs, preserve focus and local order
      if (!this.plan.id && srvPlan.id) {
        this.plan.id = srvPlan.id;
        // Update URL to resume version (silent push)
        try {
          const newUrl = `/allenamenti/wizard/${srvPlan.id}/`;
          if (window.history && window.location.pathname !== newUrl) {
            window.history.replaceState({}, '', newUrl);
          }
        } catch (e) { /* ignore */ }
      }
      if (Array.isArray(srvPlan.days)) {
        srvPlan.days.forEach((srvDay, i) => {
          const localDay = this.plan.days[i];
          if (!localDay) return;
          if (!localDay.pk && srvDay.pk) localDay.pk = srvDay.pk;
          if (Array.isArray(srvDay.exercises)) {
            srvDay.exercises.forEach((srvEx, j) => {
              const localEx = localDay.exercises[j];
              if (localEx && !localEx.pk && srvEx.pk) localEx.pk = srvEx.pk;
            });
          }
        });
      }

      if (srvPlan.progression) {
        this._mergeProgressionFromServer(srvPlan.progression);
      }
    },

    _mergeProgressionFromServer(srvProg) {
      // Weeks: replace local copy with server (authoritative).
      this.progression.weeks = (srvProg.weeks || []).map(w => ({ ...w }));

      // Rules: assign server pks to rules created locally that match exercise+subtype+order.
      const srvRules = srvProg.rules || [];
      srvRules.forEach(srvR => {
        const local = this.progression.rules.find(r =>
          !r.id &&
          this._resolveExerciseId(r) === srvR.workout_exercise_id &&
          r.subtype === srvR.subtype &&
          (r.order_index || 0) === (srvR.order_index || 0)
        );
        if (local) {
          local.id = srvR.id;
        }
      });
      // Drop client-only rules not echoed back (server-validated removal).
      // Simpler: replace local rules with srvRules but preserve `_exercise_local_id` mapping when possible.
      this.progression.rules = srvRules.map(r => ({ ...r }));

      this.progression.overrides = (srvProg.overrides || []).map(o => ({ ...o }));
      this.progression.computed = srvProg.computed || {};
    },

    _resolveExerciseId(rule) {
      if (typeof rule.workout_exercise_id === 'number') return rule.workout_exercise_id;
      if (rule._exercise_local_id) {
        for (const d of this.plan.days) {
          for (const ex of d.exercises) {
            if (ex.local_id === rule._exercise_local_id && ex.pk) return ex.pk;
          }
        }
      }
      return null;
    },

    _beforeUnload(e) {
      if (this.saveState !== 'saving' && this.saveState !== 'error') return;
      // Best-effort sendBeacon for last save
      try {
        const url = this.plan.id
          ? this.urls.save.replace('__ID__', this.plan.id)
          : this.urls.save_new;
        const blob = new Blob([JSON.stringify(this._serializePlan())], { type: 'application/json' });
        if (navigator.sendBeacon) navigator.sendBeacon(url, blob);
      } catch (err) { /* ignore */ }
    },

    _resetIdleTimer() {
      if (this.idleTimer) clearTimeout(this.idleTimer);
      this.idleTimer = setTimeout(() => this.saveDraft(), 3 * 60 * 1000);
    },

    get lastSavedLabel() {
      if (!this.lastSavedAt) return 'Bozza';
      const h = String(this.lastSavedAt.getHours()).padStart(2, '0');
      const m = String(this.lastSavedAt.getMinutes()).padStart(2, '0');
      return `Salvato ${h}:${m}`;
    },

    // ---- Step 3: assignment / finalize ----
    async loadClients() {
      const params = new URLSearchParams();
      if (this.clientQuery) params.set('q', this.clientQuery);
      try {
        const r = await fetch(`${this.urls.search_clients}?${params.toString()}`);
        this.clientsList = await r.json();
      } catch (e) {
        this.clientsList = [];
      }
    },

    toggleClient(id) {
      const i = this.selectedClientIds.indexOf(id);
      if (i >= 0) this.selectedClientIds.splice(i, 1);
      else this.selectedClientIds.push(id);
    },

    async _finalize(payload) {
      if (!this.plan.id) {
        await this.saveDraft();
      }
      if (!this.plan.id) {
        this.errors.finalize = 'Impossibile salvare la scheda.';
        return null;
      }
      this.finalizing = true;
      this.errors.finalize = '';
      this.errors.assign = '';
      try {
        const r = await fetch(this.urls.finalize.replace('__ID__', this.plan.id), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this.getCsrf() },
          body: JSON.stringify(payload),
        });
        const d = await r.json();
        if (!r.ok) {
          this.errors.finalize = d.error || 'Errore.';
          return null;
        }
        return d;
      } catch (e) {
        this.errors.finalize = 'Errore di rete.';
        return null;
      } finally {
        this.finalizing = false;
      }
    },

    async doAssign() {
      if (this.selectedClientIds.length === 0) {
        this.errors.assign = 'Seleziona almeno un cliente.';
        return;
      }
      const weeks = this.assignWeeks || this.plan.duration_weeks;
      if (!weeks || weeks < 1) {
        this.errors.assign = 'Durata scheda mancante.';
        return;
      }
      // Ensure latest state on server
      await this.saveDraft();
      const d = await this._finalize({
        action: 'assign',
        client_ids: this.selectedClientIds,
        weeks: weeks,
      });
      if (d) {
        this._showToast('Scheda assegnata!');
        setTimeout(() => { window.location.href = d.redirect_url || this.urls.list; }, 1200);
      }
    },

    async doSaveTemplate() {
      await this.saveDraft();
      const d = await this._finalize({ action: 'template' });
      if (d) {
        this._showToast('Salvata come template');
        setTimeout(() => { window.location.href = d.redirect_url || this.urls.list; }, 1200);
      }
    },

    _showToast(msg) {
      this.toast = msg;
      setTimeout(() => { this.toast = ''; }, 2000);
    },

    // ============================================================
    // Progressione module
    // ============================================================
    _hydrateProgression(srvProg) {
      this.progression.weeks = (srvProg.weeks || []).map(w => ({ ...w }));
      this.progression.rules = (srvProg.rules || []).map(r => ({ ...r }));
      this.progression.overrides = (srvProg.overrides || []).map(o => ({ ...o }));
      this.progression.computed = srvProg.computed || {};
      this.progression.conflicts = srvProg.conflicts || [];
      this.progUi.activeWeek = 1;
    },

    weekNumbers() {
      const dur = this.plan?.duration_weeks || 1;
      const out = [];
      for (let i = 1; i <= dur; i++) out.push(i);
      return out;
    },

    weekTypeOf(weekNumber) {
      const w = (this.progression.weeks || []).find(x => x.week_number === weekNumber);
      return (w && w.week_type) || 'STANDARD';
    },

    weekTypeShort(type) {
      return ({ DELOAD: 'DL', TEST: 'TEST', TECHNIQUE: 'TEC', RECOVERY: 'REC' })[type] || '';
    },

    async setWeekType(weekNumber, newType) {
      if (!this.plan.id) {
        await this.saveDraft();
      }
      if (!this.plan.id) return;
      // Optimistic local update.
      let local = this.progression.weeks.find(w => w.week_number === weekNumber);
      if (!local) {
        local = { week_number: weekNumber, label: '', preset: '', notes: '', week_type: 'STANDARD' };
        this.progression.weeks = [...this.progression.weeks, local];
      }
      const previous = local.week_type;
      local.week_type = newType;

      try {
        const url = `/api/allenamenti/${this.plan.id}/progression/week/${weekNumber}/special/`;
        const r = await fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this.getCsrf() },
          body: JSON.stringify({ week_type: newType }),
        });
        if (!r.ok) {
          local.week_type = previous;
          this._showToast('Errore aggiornamento settimana');
          return;
        }
        // Trigger reload of weekly values via plain save (which recomputes server-side).
        await this.saveDraft();
      } catch (e) {
        local.week_type = previous;
      }
    },

    toggleDayOpen(localId) {
      this.progUi.openDays = { ...this.progUi.openDays, [localId]: !this.progUi.openDays[localId] };
    },

    dayOpen(localId) {
      // First day open by default.
      if (!(localId in this.progUi.openDays)) {
        const firstId = this.plan.days[0]?.local_id;
        return localId === firstId;
      }
      return !!this.progUi.openDays[localId];
    },

    rulesForExercise(ex) {
      if (!ex) return [];
      const exId = ex.pk;
      const exLocal = ex.local_id;
      return this.progression.rules.filter(r =>
        (exId && r.workout_exercise_id === exId) ||
        (r._exercise_local_id && r._exercise_local_id === exLocal)
      );
    },

    ruleChipLabel(r) {
      const fam = this.FAMILY_DEFS.find(f => f.value === r.family)?.label || r.family;
      const subList = this.SUBTYPE_MAP[r.family] || [];
      const sub = subList.find(s => s.value === r.subtype)?.label || r.subtype;
      return `${fam} · ${sub.split(' (')[0]}`;
    },

    ruleSummary(r) {
      const p = r.parameters || {};
      switch (r.subtype) {
        case 'LOAD_LINEAR': case 'LOAD_MICRO':
          return `+${p.delta || 0} ${p.unit || 'KG'} ogni ${p.every_n_weeks || 1} sett. (S${r.start_week}${r.end_week ? '–S'+r.end_week : ''})`;
        case 'LOAD_PERCENT':
          return `+${p.delta_pct || 0}% ogni ${p.every_n_weeks || 1} sett.`;
        case 'VOL_DOUBLE':
          return `Reps ${p.rep_low || 8}→${p.rep_high || 12}, +${p.load_step || 2.5} kg al rollover`;
        case 'INT_RPE': case 'INT_RIR': case 'INT_PCT1RM':
        case 'LOAD_MANUAL': case 'TEMPO_PRESET': case 'VEL_TARGET':
        case 'UND_WUP': case 'UND_DUP':
          return Object.entries(p.by_week || {}).map(([w,v])=>`S${w}:${v}`).join(' · ') || 'Valori per settimana';
        case 'DEN_REST':
          return `${p.start_seconds || ''}s → ${p.delta_seconds || 0}s/sett (min ${p.min_seconds || 0}s)`;
        case 'DEL_AUTO':
          return `Deload su S${(p.on_weeks || []).join(', S')} · load ×${p.load_factor || 0.6}`;
        case 'ROM_INCREASE':
          return `${(p.stages || []).join(' → ')} · ${p.weeks_per_stage || 1} sett/stadio`;
        default:
          return r.label || '';
      }
    },

    computedCell(ex, week) {
      if (!ex) return {};
      const key = ex.pk ? String(ex.pk) : null;
      if (!key) return {};
      const exCells = this.progression.computed?.[key];
      if (!exCells) return {};
      return exCells[String(week)] || {};
    },

    formatCell(ex, week) {
      const c = this.computedCell(ex, week);
      const sets = c.set_count ?? ex.sets;
      const reps = c.rep_range || ex.reps;
      const load = c.load_value ?? ex.load_value;
      const unit = c.load_unit || ex.load_unit;
      const rest = c.recovery_seconds ?? ex.recovery_seconds;
      const rpe = c.rpe;
      const parts = [`${sets}×${reps}`];
      if (load !== null && load !== undefined && load !== '') {
        parts.push(`@${load}${unit === 'KG' ? 'kg' : unit === 'PERCENT_1RM' ? '%' : 'BW'}`);
      }
      if (rpe) parts.push(`RPE ${rpe}`);
      if (rest) parts.push(`${rest}s`);
      if (c.is_deload) parts.push('· deload');
      return parts.join(' ');
    },

    cellIsOverride(ex, week) {
      return !!this.computedCell(ex, week).is_override;
    },

    // ---- Drawer ----
    openProgressionDrawer(ex) {
      this.progUi.activeExercise = ex;
      this.progUi.drawerOpen = true;
      this.progUi.drawerMode = 'list';
      this.draftRule = null;
      this.progUi.draftRule = null;
    },

    closeProgressionDrawer() {
      this.progUi.drawerOpen = false;
      this.progUi.drawerMode = 'list';
      this.draftRule = null;
      this.progUi.draftRule = null;
    },

    startAddRule() {
      const ex = this.progUi.activeExercise;
      if (!ex) return;
      this.draftRule = {
        _local_id: 'r-' + Date.now() + '-' + Math.random().toString(36).slice(2, 6),
        id: null,
        workout_exercise_id: ex.pk || null,
        _exercise_local_id: ex.local_id,
        order_index: this.rulesForExercise(ex).length,
        family: '',
        subtype: '',
        target_metric: '',
        application_mode: 'FIXED_INCREMENT',
        start_week: 1,
        end_week: null,
        parameters: {},
        stackable: true,
        conflict_strategy: 'LAST_WINS',
        label: '',
      };
      this.progUi.drawerMode = 'add';
      this.progUi.previewComputed = {};
    },

    startEditRule(r) {
      this.draftRule = JSON.parse(JSON.stringify(r));
      if (!this.draftRule._exercise_local_id && this.progUi.activeExercise) {
        this.draftRule._exercise_local_id = this.progUi.activeExercise.local_id;
      }
      this.progUi.drawerMode = 'edit';
      this.paramChanged();
    },

    pickFamily(family) {
      this.draftRule.family = family;
      this.draftRule.subtype = '';
      this.draftRule.target_metric = '';
      this.draftRule.parameters = {};
    },

    subtypesFor(family) {
      return (this.SUBTYPE_MAP[family] || []).filter(s => !this.HIDDEN_SUBTYPES.includes(s.value));
    },

    visibleFamilies() {
      return this.FAMILY_DEFS.filter(f => !this.HIDDEN_FAMILIES.includes(f.value));
    },

    pickSubtype(subtype) {
      const def = (this.SUBTYPE_MAP[this.draftRule.family] || []).find(s => s.value === subtype);
      if (!def) return;
      this.draftRule.subtype = subtype;
      this.draftRule.target_metric = def.metric;
      this.draftRule.application_mode = def.mode;
      this.draftRule.parameters = this._defaultParamsFor(subtype);
      this.paramChanged();
    },

    _defaultParamsFor(subtype) {
      const dur = this.plan.duration_weeks || 4;
      switch (subtype) {
        case 'LOAD_LINEAR': return { delta: 2.5, unit: 'KG', every_n_weeks: 1 };
        case 'LOAD_PERCENT': return { delta_pct: 2.5, round_to: 1.25, every_n_weeks: 1 };
        case 'LOAD_MICRO': return { delta: 0.5, unit: 'KG', every_n_weeks: 1 };
        case 'LOAD_MANUAL': return { by_week: {} };
        case 'VOL_SETS': return { start: 3, end: 5, step: 1, every_n_weeks: 1 };
        case 'VOL_REPS': return { min: 8, max: 12, step: 1, every_n_weeks: 1 };
        case 'VOL_DOUBLE': return { rep_low: 8, rep_high: 12, load_step: 2.5, every_n_weeks: 1, load_unit: 'KG' };
        case 'INT_RPE': return { by_week: {} };
        case 'INT_RIR': return { by_week: {} };
        case 'INT_PCT1RM': return { by_week: {} };
        case 'DEN_REST': return { delta_seconds: -10, min_seconds: 60, every_n_weeks: 1 };
        case 'TEMPO_PRESET': return { by_week: {} };
        case 'ROM_INCREASE': return { stages: ['partial','mid','full'], weeks_per_stage: 1 };
        case 'VAR_TRANSITION': return { by_week: {} };
        case 'UND_WUP': return { by_week: {} };
        case 'UND_DUP': return { by_week: {} };
        case 'DEL_AUTO': {
          const onWeeks = dur >= 8 ? [4, 8] : (dur >= 4 ? [dur] : []);
          return { on_weeks: onWeeks, load_factor: 0.6, volume_factor: 0.5, rpe_cap: 6 };
        }
        case 'VEL_TARGET': return { by_week: {} };
        default: return {};
      }
    },

    setByWeek(week, value) {
      this.draftRule.parameters = { ...this.draftRule.parameters };
      const map = { ...(this.draftRule.parameters.by_week || {}) };
      if (value === '' || value === null || value === undefined) {
        delete map[String(week)];
      } else {
        map[String(week)] = value;
      }
      this.draftRule.parameters.by_week = map;
      this.paramChanged();
    },

    setOnWeeks(csv) {
      const arr = csv.split(',').map(s => parseInt(s.trim(), 10)).filter(n => !isNaN(n));
      this.draftRule.parameters = { ...this.draftRule.parameters, on_weeks: arr };
      this.paramChanged();
    },

    setStages(csv) {
      const arr = csv.split(',').map(s => s.trim()).filter(Boolean);
      this.draftRule.parameters = { ...this.draftRule.parameters, stages: arr };
      this.paramChanged();
    },

    paramChanged() {
      if (this.progUi.previewTimer) clearTimeout(this.progUi.previewTimer);
      this.progUi.previewTimer = setTimeout(() => this.fetchLivePreview(), 250);
    },

    async fetchLivePreview() {
      const ex = this.progUi.activeExercise;
      if (!ex || !ex.pk || !this.plan.id || !this.draftRule || !this.draftRule.subtype) {
        this.progUi.previewComputed = {};
        return;
      }
      // Build combined rule set: existing rules on this exercise + draft (replacing if editing).
      const existing = this.rulesForExercise(ex).filter(r => r._local_id !== this.draftRule._local_id && r.id !== this.draftRule.id);
      const draftCopy = { ...this.draftRule };
      if (draftCopy.id == null) draftCopy.id = -1;
      const rulesPayload = [...existing, draftCopy].map(r => ({
        id: r.id,
        order_index: r.order_index || 0,
        family: r.family,
        subtype: r.subtype,
        target_metric: r.target_metric,
        application_mode: r.application_mode,
        start_week: r.start_week,
        end_week: r.end_week,
        parameters: r.parameters,
        stackable: r.stackable !== false,
        conflict_strategy: r.conflict_strategy || 'LAST_WINS',
      }));
      const overridesPayload = (this.progression.overrides || []).filter(o => o.workout_exercise_id === ex.pk);

      try {
        const r = await fetch(`/api/allenamenti/${this.plan.id}/progression/preview/`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this.getCsrf() },
          body: JSON.stringify({
            workout_exercise_id: ex.pk,
            rules: rulesPayload,
            overrides: overridesPayload,
          }),
        });
        if (!r.ok) return;
        const d = await r.json();
        this.progUi.previewComputed = d.computed || {};
      } catch (e) { /* silent */ }
    },

    previewCell(week) {
      const c = this.progUi.previewComputed?.[String(week)];
      if (!c) return '—';
      const ex = this.progUi.activeExercise;
      const sets = c.set_count ?? ex?.sets;
      const reps = c.rep_range || ex?.reps;
      const load = c.load_value;
      const unit = c.load_unit || (ex?.load_unit);
      const rpe = c.rpe;
      const parts = [`${sets}×${reps}`];
      if (load !== null && load !== undefined && load !== '') {
        parts.push(`@${load}${unit === 'KG' ? 'kg' : unit === 'PERCENT_1RM' ? '%' : 'BW'}`);
      }
      if (rpe) parts.push(`RPE${rpe}`);
      return parts.join(' ');
    },

    canSaveDraftRule() {
      return !!(this.draftRule && this.draftRule.family && this.draftRule.subtype);
    },

    saveDraftRule() {
      if (!this.canSaveDraftRule()) return;
      const r = this.draftRule;
      if (r.id != null) {
        // edit: replace in array
        this.progression.rules = this.progression.rules.map(x =>
          (x.id === r.id || x._local_id === r._local_id) ? { ...r } : x
        );
      } else {
        this.progression.rules = [...this.progression.rules, { ...r }];
      }
      this.draftRule = null;
      this.progUi.drawerMode = 'list';
      this.progUi.previewComputed = {};
      this.markDirty();
    },

    cancelDraftRule() {
      this.draftRule = null;
      this.progUi.drawerMode = 'list';
      this.progUi.previewComputed = {};
    },

    removeRule(r) {
      if (!confirm('Rimuovere questa progressione? I valori delle settimane saranno ricalcolati.')) return;
      this.progression.rules = this.progression.rules.filter(x =>
        !(x.id === r.id && x._local_id === r._local_id) &&
        !(r.id != null && x.id === r.id) &&
        !(r._local_id && x._local_id === r._local_id)
      );
      this.markDirty();
    },
  }));
});
