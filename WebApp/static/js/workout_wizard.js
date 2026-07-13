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

    library: {
      query: '', muscle_slug: '', equipment_id: '', category_id: '',
      custom_only: false,
      items: [], loading: false,
    },
    filters: { muscles: [], equipment: [], categories: [] },
    muscleGroups: [],
    foldersCatalog: [],

    /* Volume drawer open tracker */
    _volumeOpen: false,
    _volumeRefreshTimer: null,

    /* Per-exercise stats drawer */
    exStats: {
      open: false,
      ex: null,
      metric: 'volume',           // 'volume' | 'load' | 'intensity'
      weeksSelected: [],
      hasData: true,              // false → show "nessun dato" alert instead of empty chart
    },
    _exStatsChart: null,
    _exStatsCanvas: null,

    /* Custom exercise drawer */
    customExerciseOpen: false,
    customExercise: {
      name: '', category_id: null, primary_muscle_ids: [], secondary_muscle_ids: [],
      equipment_ids: [], coach_notes: '',
      saving: false, error: '',
    },

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
    assignDurationValue: null,
    assignDurationUnit: 'WEEKS',
    finalizing: false,
    overwriteConfirmed: false,
    recapDaysOpen: {},

    errors: { step1: '', step2: '', assign: '', finalize: '' },
    toast: '',

    urls: window.WIZARD_URLS,

    // ---- Progression state ----
    progression: { weeks: [], rules: [], overrides: [], computed: {}, conflicts: [] },

    // Per-day grid for new Step 3 UI (server-fetched, replaces local progression accordion).
    progGrid: {
      dayIdx: 0,           // index into plan.days
      windowStart: 1,      // leftmost visible week
      windowSize: 3,       // visible columns
      exercises: [],       // [{id, exercise_id, name, starts_at_week, base:{...}}, ...] for current day
      cells: {},           // {ex_id: {week: {metric: {value, source, override_week}}}}
      expanded: {},        // {ex_id: bool} — expanded shows Carico/RPE/RIR row
      slideDir: 0,         // -1 = slide-in from left, 1 = slide-in from right, 0 = no anim
      loading: false,
    },

    // Delete-cell confirm modal
    deleteUi: {
      open: false,
      exId: null,
      exName: '',
      week: 1,
    },

    // Add-exercise-at-week drawer
    addExUi: {
      open: false,
      week: 1,
      dayIdx: 0,
      query: '',
      results: [],
      loading: false,
    },

    progUi: {
      activeWeek: 1,
      activeExercise: null,
      drawerOpen: false,
      drawerMode: 'list',
      openDays: {},
      draftRule: null,
      previewComputed: {},
      previewTimer: null,
      chartType: 'histogram', // histogram | line (removed metric selector)
      secondaryMode: 'total', // total | primary | secondary
    },
    progComputedGroups: [],
    progGroupsSelected: [],
    _progChart: null,
    _progCanvas: null,
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
      const urlParams = new URLSearchParams(window.location.search);
      const kindParam = (urlParams.get('kind') || '').toUpperCase();
      const folderParam = parseInt(urlParams.get('folder_id') || '0', 10);

      const initialKind = init.plan_kind || (kindParam === 'PROGRAM' ? 'PROGRAM' : (kindParam === 'WEEKLY' ? 'WEEKLY' : 'WEEKLY'));

      this.plan = {
        id: init.id || null,
        title: init.title || '',
        description: init.description || '',
        goal: init.goal || '',
        level: init.level || '',
        frequency_per_week: init.frequency_per_week || 4,
        duration_weeks: init.duration_weeks || (initialKind === 'PROGRAM' ? 4 : 1),
        status: init.status || 'DRAFT',
        last_step: init.last_step || 1,
        folder_id: init.folder_id || (folderParam || null),
        plan_kind: initialKind,
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

      // Initialize progression volume visualization
      this.$nextTick(() => {
        this._computeProgVolume();
        // Watch for week changes to update volume visualization
        this.$watch('progUi.activeWeek', () => { this._computeProgVolume(); this._refreshProgChart(); });
        // Watch for progression changes to update volume
        this.$watch('progression.rules.length', () => { this._computeProgVolume(); this._refreshProgChart(); });
      });
      this.loadMuscleGroups();
      this.loadFoldersCatalog();
      this.loadLibrary();

      // Volume drawer close → clear flag
      window.addEventListener('volume-analytics:closed', () => { this._volumeOpen = false; });

      // Beforeunload save
      window.addEventListener('beforeunload', (e) => this._beforeUnload(e));

      // Idle timer
      this._resetIdleTimer();
      ['mousemove', 'keydown', 'click'].forEach(evt =>
        document.addEventListener(evt, () => this._resetIdleTimer(), { passive: true })
      );

      // Re-render progression chart when relevant state changes.
      this.$watch('step', (v) => {
        if (v === 3) {
          setTimeout(() => this._refreshProgChart(), 250);
          // Load per-day grid for new Step 3 UI.
          this.loadProgGrid();
        }
      });
      // If init resumed directly at step 3 (page reload), the $watch above never
      // fires — trigger an initial load explicitly.
      if (this.step === 3) {
        this.$nextTick(() => this.loadProgGrid());
      }
      this.$watch('progUi.activeWeek', () => this._refreshProgChart());
      this.$watch('progression.rules', () => {
        this._refreshProgChart();
        if (this.exStats.open) this.renderExStatsChart();
      });
      this.$watch('progression.computed', () => {
        if (this.exStats.open) this.renderExStatsChart();
      });

      // Close per-exercise stats drawer on Esc.
      window.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && this.exStats.open) this.closeExerciseStats();
      });
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
          primary_muscles_data: ex.primary_muscles || [],
          secondary_muscles_data: ex.secondary_muscles || [],
          equipment: ex.equipment || [],
          sets: ex.sets ?? 3,
          reps: ex.reps ?? '10',
          load_value: ex.load_value ?? null,
          load_unit: ex.load_unit || 'KG',
          recovery_seconds: ex.recovery_seconds ?? 90,
          notes: ex.notes ?? ex.coach_notes ?? '',
          coach_notes: ex.coach_notes ?? ex.notes ?? '',
          execution_type: ex.execution_type || 'REPETITION',
          rpe: ex.rpe ?? null,
          rir: ex.rir ?? null,
          tempo: ex.tempo || '',
          superset_group_id: ex.superset_group_id ?? null,
          set_details: Array.isArray(ex.set_details) ? ex.set_details : [],
          /* UI-only */
          _showAdvanced: !!(ex.rpe || ex.rir || ex.tempo),
          _showNote: !!(ex.notes || ex.coach_notes),
          _rpe_rir_type: (ex.rir != null && ex.rir !== '') ? 'RIR' : 'RPE',
        })),
      }));
    },

    // ---- CSRF helper ----
    getCsrf() {
      return window.csrfToken();
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

    goToStep(targetStep) {
      // Navigate to a specific step, with validation
      if (targetStep === this.step) return;
      if (targetStep < 1 || targetStep > 4) return;

      // Can always go backward
      if (targetStep < this.step) {
        this.step = targetStep;
        if (this.step === 2) this.$nextTick(() => this.bindSortable());
        return;
      }

      // Going forward: validate each step
      let currentStep = this.step;
      while (currentStep < targetStep) {
        if (currentStep === 1) {
          if (!this.canAdvanceStep1()) {
            this.errors.step1 = 'Compila titolo e numero allenamenti per settimana.';
            return;
          }
          this.errors.step1 = '';
          this._ensureDays();
          currentStep = 2;
        } else if (currentStep === 2) {
          if (!this.canAdvanceStep2()) {
            this.errors.step2 = 'Aggiungi almeno un esercizio in almeno un giorno.';
            return;
          }
          this.errors.step2 = '';
          currentStep = this.hasProgressionStep() ? 3 : 4;
        } else if (currentStep === 3) {
          currentStep = 4;
        }
      }
      this.step = targetStep;
      this.plan.last_step = targetStep;
      this.$nextTick(() => this.bindSortable());
      this.saveDraft();
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
    /**
     * Build a <select> dropdown via DOM API. Bypasses the well-known
     * <template x-for>-inside-<select> parser issue and keeps the value
     * synced when the source array updates.
     *
     * @param el        the <select> element
     * @param emptyLbl  label for the "all" option (value="")
     * @param getList   () => array
     * @param valueKey  property to use as option value (null = use the item itself)
     * @param labelKey  property to use as label (null = use the item itself)
     * @param getCur    () => currently-selected value
     */
    // Filter selects now rendered inline via <template x-for> in wizard.html;
    // helper kept as no-op for backwards compat with any stale templates.
    renderFilterSelect() { /* deprecated */ },

    async loadFilters() {
      try {
        const r = await fetch(this.urls.filters);
        const d = await r.json();
        this.filters = d;
      } catch (e) { /* silent */ }
    },

    async loadMuscleGroups() {
      try {
        const r = await fetch(this.urls.muscle_groups || '/api/muscle-groups/');
        this.muscleGroups = await r.json();
      } catch (e) { this.muscleGroups = []; }
    },

    async loadFoldersCatalog() {
      try {
        const r = await fetch(this.urls.folders || '/api/allenamenti/cartelle/');
        this.foldersCatalog = await r.json();
      } catch (e) { this.foldersCatalog = []; }
    },

    async loadLibrary() {
      this.library.loading = true;
      const params = new URLSearchParams();
      if (this.library.query) params.set('q', this.library.query);
      if (this.library.muscle_slug) params.set('muscle_slug', this.library.muscle_slug);
      if (this.library.equipment_id) params.set('equipment_id', this.library.equipment_id);
      if (this.library.category_id) params.set('category_id', this.library.category_id);
      if (this.library.custom_only) params.set('custom', 'true');

      try {
        const r = await fetch(`${this.urls.search_exercises}?${params.toString()}`);
        this.library.items = await r.json();
      } catch (e) {
        this.library.items = [];
      } finally {
        this.library.loading = false;
      }
    },

    /* ---- Volume Analytics Drawer ---- */
    _muscleByName() {
      const m = {};
      (this.muscleGroups || []).forEach(g => { m[g.name.toLowerCase()] = g; });
      return m;
    },

    _resolvedExerciseMuscles(ex) {
      return { primary: ex.primary_muscles_data || [], secondary: ex.secondary_muscles_data || [] };
    },

    /* Builder volume payload: single week, base sets only. */
    _buildVolumePayload() {
      const days = (this.plan?.days || []).map(d => ({
        name: d.name,
        exercises: (d.exercises || []).map(ex => {
          const { primary, secondary } = this._resolvedExerciseMuscles(ex);
          return {
            sets: parseInt(ex.sets, 10) || 0,
            reps: ex.reps || '',
            primary_muscles: primary,
            secondary_muscles: secondary,
            primary_muscle_text: primary[0]?.name || '',
          };
        }),
      }));

      return {
        planKind: this.plan.plan_kind || 'WEEKLY',
        durationWeeks: 1,  // builder always shows the single working week
        days,
      };
    },

    /* Progression volume payload: full duration, per-week sets from computed cells. */
    _buildProgressionVolumePayload() {
      const computed = this.progression?.computed || {};
      const dur = Math.max(1, parseInt(this.plan.duration_weeks, 10) || 1);

      const days = (this.plan?.days || []).map(d => ({
        name: d.name,
        exercises: (d.exercises || []).map(ex => {
          const { primary, secondary } = this._resolvedExerciseMuscles(ex);
          const baseSets = parseInt(ex.sets, 10) || 0;
          const exComputed = ex.pk ? (computed[String(ex.pk)] || {}) : {};
          const weekly_overrides = {};
          for (let w = 1; w <= dur; w++) {
            const cell = exComputed[String(w)] || {};
            const sets = (cell.set_count != null) ? parseInt(cell.set_count, 10) : baseSets;
            weekly_overrides[w] = { sets, reps: cell.rep_range || ex.reps || '' };
          }
          return {
            sets: baseSets,
            reps: ex.reps || '',
            primary_muscles: primary,
            secondary_muscles: secondary,
            primary_muscle_text: primary[0]?.name || '',
            weekly_overrides,
          };
        }),
      }));

      return {
        planKind: this.plan.plan_kind || 'PROGRAM',
        durationWeeks: dur,
        days,
        progressionMode: true,
        hideRadar: true,
        defaultWeek: this.progUi.activeWeek || 1,
      };
    },

    openVolumeAnalytics() {
      this._volumeOpen = true;
      window.AthlynkVolume.open(this._buildVolumePayload());
    },

    openProgressionVolumeAnalytics() {
      this._volumeOpen = true;
      window.AthlynkVolume.open(this._buildProgressionVolumePayload());
    },

    _refreshVolumeIfOpen() {
      if (!this._volumeOpen) return;
      if (this._volumeRefreshTimer) clearTimeout(this._volumeRefreshTimer);
      const payload = (this.step === 3)
        ? this._buildProgressionVolumePayload()
        : this._buildVolumePayload();
      this._volumeRefreshTimer = setTimeout(() => {
        window.AthlynkVolume.refresh(payload);
      }, 250);
    },

    /* ---- Custom exercise drawer ---- */
    openCustomExerciseDrawer() {
      this.customExerciseOpen = true;
      window.panelLock && window.panelLock.acquire();
      this.customExercise = {
        name: '', category_id: null,
        primary_muscle_ids: [], secondary_muscle_ids: [],
        equipment_ids: [], coach_notes: '',
        saving: false, error: '',
      };
    },
    closeCustomExerciseDrawer() {
      if (this.customExerciseOpen) window.panelLock && window.panelLock.release();
      this.customExerciseOpen = false;
    },
    toggleCustomMuscle(arrName, id) {
      const arr = this.customExercise[arrName];
      const i = arr.indexOf(id);
      if (i >= 0) arr.splice(i, 1); else arr.push(id);
    },

    async saveCustomExercise(addToBuilderAfter) {
      const ce = this.customExercise;
      ce.error = '';
      if ((ce.name || '').trim().length < 3) { ce.error = 'Nome: minimo 3 caratteri.'; return; }
      if (!ce.primary_muscle_ids.length) { ce.error = 'Seleziona almeno un muscolo primario.'; return; }
      ce.saving = true;
      try {
        const r = await fetch(this.urls.custom_exercises || '/api/exercises/custom/', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this.getCsrf() },
          body: JSON.stringify({
            name: ce.name.trim(),
            category_id: ce.category_id,
            primary_muscle_ids: ce.primary_muscle_ids,
            secondary_muscle_ids: ce.secondary_muscle_ids,
            equipment_ids: ce.equipment_ids,
            coach_notes: ce.coach_notes,
          }),
        });
        const d = await r.json();
        if (!r.ok) { ce.error = d.error || 'Errore di salvataggio.'; ce.saving = false; return; }
        // Add to library
        this.library.items.unshift({
          id: d.id, name: d.name, is_custom: true,
          category: d.category || null,
          equipment: d.equipment || [],
          primary_muscles: d.primary_muscles || [],
          secondary_muscles: d.secondary_muscles || [],
        });
        this._showToast('Esercizio personalizzato salvato.');
        this.closeCustomExerciseDrawer();
        if (addToBuilderAfter) this.addExerciseToActiveDay(d);
      } catch (e) { ce.error = 'Errore di rete.'; }
      ce.saving = false;
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
        primary_muscles_data: libEx.primary_muscles || [],
        secondary_muscles_data: libEx.secondary_muscles || [],
        equipment: libEx.equipment || [],
        sets: 3,
        reps: '10',
        load_value: null,
        load_unit: 'KG',
        recovery_seconds: 90,
        notes: '',
        coach_notes: '',
        execution_type: 'REPETITION',
        rpe: null,
        rir: null,
        tempo: '',
        superset_group_id: null,
        set_details: [],
        _showAdvanced: false,
        _showNote: false,
        _rpe_rir_type: 'RPE',
      });
      this.flashIds.push(libEx.id);
      setTimeout(() => {
        this.flashIds = this.flashIds.filter(x => x !== libEx.id);
      }, 600);
      this.markDirty();
      this.$nextTick(() => this.bindSortable());
    },

    async removeExercise(idx) {
      const day = this.activeDay();
      if (!day) return;
      const ex = day.exercises[idx];
      const label = ex?.exercise_name || 'questo esercizio';
      if (!await window.alConfirm({ icon: 'ph-trash', title: 'Rimuovere\nl\'esercizio?', subtitle: '«' + label + '» verrà rimosso dal giorno.', confirmLabel: 'Sì, rimuovi' })) return;
      day.exercises.splice(idx, 1);
      this.markDirty();
    },

    /* Build one per-set row prefilled from the exercise's base values. */
    _blankSetRow(ex) {
      return {
        reps: ex.reps ?? '',
        load_value: ex.load_value ?? null,
        load_unit: ex.load_unit || 'KG',
        recovery_seconds: ex.recovery_seconds ?? null,
        rpe: ex.rpe ?? null,
        rir: ex.rir ?? null,
        tempo: ex.tempo || '',
      };
    },

    /* Toggle per-set editing: expand into N rows (N = sets) or collapse to uniform. */
    toggleSetDetails(ex) {
      if (ex.set_details && ex.set_details.length) {
        ex.set_details = [];
      } else {
        const n = Math.max(1, parseInt(ex.sets, 10) || 1);
        ex.set_details = Array.from({ length: n }, () => this._blankSetRow(ex));
      }
      this.markDirty();
    },

    /* Keep the per-set rows in sync when the set count changes while expanded. */
    syncSetDetails(ex) {
      if (!ex.set_details || !ex.set_details.length) return;
      const n = Math.max(1, parseInt(ex.sets, 10) || 1);
      while (ex.set_details.length < n) ex.set_details.push(this._blankSetRow(ex));
      if (ex.set_details.length > n) ex.set_details.length = n;
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
        draggable: '.wb-row',
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
          const primary = ex.primary_muscles_data?.[0]?.name;
          const secondary = ex.secondary_muscles_data?.[0]?.name;
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

    // ---- Chart.js progression chart (Step 3) ----
    dayRulesCount(d) {
      if (!d || !d.exercises) return 0;
      return d.exercises.reduce((sum, ex) => sum + this.rulesForExercise(ex).length, 0);
    },

    setProgMetric(m) {
      if (this.progUi.chartMetric === m) return;
      this.progUi.chartMetric = m;
      this.renderProgChart();
    },
    setProgChartType(t) {
      if (this.progUi.chartType === t) return;
      this.progUi.chartType = t;
      this._refreshProgChart();
    },

    setProgSecondaryMode(mode) {
      if (this.progUi.secondaryMode === mode) return;
      this.progUi.secondaryMode = mode;
      this._computeProgVolume();
      this._refreshProgChart();
    },

    toggleProgGroup(slug) {
      const i = this.progGroupsSelected.indexOf(slug);
      if (i >= 0) this.progGroupsSelected.splice(i, 1);
      else this.progGroupsSelected.push(slug);
      this._refreshProgChart();
    },

    selectAllProgGroups() {
      this.progGroupsSelected = this.progComputedGroups.map(g => g.slug);
      this._refreshProgChart();
    },

    groupColor(g) {
      const MG_PALETTE = {
        'mg-chest': '#9C4448',
        'mg-back': '#1E3A5F',
        'mg-shoulders': '#8A6E5A',
        'mg-quads': '#3F7690',
        'mg-hams': '#4F7A6A',
        'mg-glutes': '#6A5482',
        'mg-calves': '#5B89B6',
        'mg-biceps': '#2B6E6E',
        'mg-triceps': '#8A6A1E',
        'mg-abs': '#4A5A8A',
        'mg-forearms': '#8A5A6B',
        'mg-other': '#5B6B78',
      };
      return MG_PALETTE[g.color_token] || '#5B6B78';
    },

    _computeProgVolume() {
      // Compute volume per muscle group for the selected week
      const week = this.progUi.activeWeek;
      const groups = new Map(); // slug -> {slug, name, color_token, volume}

      const computed = this.progression?.computed || {};
      this.plan.days.forEach(day => {
        (day.exercises || []).forEach(ex => {
          const primaries = ex.primary_muscles || [];
          const secondaries = ex.secondary_muscles || [];
          const baseSets = parseInt(ex.sets, 10) || 0;

          const cell = ex.pk ? (computed[String(ex.pk)]?.[String(week)] || {}) : {};
          const sets = (cell.set_count != null ? parseInt(cell.set_count, 10) : baseSets) || 0;

          primaries.forEach(m => {
            if (!groups.has(m.slug)) {
              groups.set(m.slug, { slug: m.slug, name: m.name, color_token: m.color_token || 'mg-other', primary: 0, secondary: 0 });
            }
            groups.get(m.slug).primary += sets;
          });

          secondaries.forEach(m => {
            if (!groups.has(m.slug)) {
              groups.set(m.slug, { slug: m.slug, name: m.name, color_token: m.color_token || 'mg-other', primary: 0, secondary: 0 });
            }
            groups.get(m.slug).secondary += sets * 0.5;
          });
        });
      });

      // Convert to array and compute final volume based on mode
      this.progComputedGroups = Array.from(groups.values()).map(g => ({
        slug: g.slug,
        name: g.name,
        color_token: g.color_token,
        volume: this.progUi.secondaryMode === 'primary' ? g.primary
               : this.progUi.secondaryMode === 'secondary' ? g.secondary
               : g.primary + g.secondary,
      })).sort((a, b) => b.volume - a.volume);

      if (this.progGroupsSelected.length === 0) {
        this.progGroupsSelected = this.progComputedGroups.map(g => g.slug);
      } else {
        // Keep only selected groups that still exist
        const slugs = this.progComputedGroups.map(g => g.slug);
        this.progGroupsSelected = this.progGroupsSelected.filter(s => slugs.includes(s));
      }
    },

    mountProgChart(el) {
      this._progCanvas = el;
      // No render here — the $watch on step handles initial paint (and any
      // re-entry to step 3) so we never double-render between mount + watch.
      if (this.step === 3) {
        setTimeout(() => this._refreshProgChart(), 250);
      }
    },

    _destroyProgChart() {
      if (this._progChart) {
        try { this._progChart.destroy(); } catch (_) { /* ignore */ }
        this._progChart = null;
      }
    },

    renderProgChart() {
      if (!this._progCanvas || typeof Chart === 'undefined') return;
      this._destroyProgChart();

      // Show volume per muscle group for selected week
      const filtered = this.progComputedGroups.filter(g => this.progGroupsSelected.includes(g.slug));
      if (filtered.length === 0) return;

      const labels = filtered.map(g => g.name);
      const data = filtered.map(g => g.volume);

      const ctx = this._progCanvas.getContext('2d');
      const MG_PALETTE = {
        'mg-chest': '#9C4448',
        'mg-back': '#1E3A5F',
        'mg-shoulders': '#8A6E5A',
        'mg-quads': '#3F7690',
        'mg-hams': '#4F7A6A',
        'mg-glutes': '#6A5482',
        'mg-calves': '#5B89B6',
        'mg-biceps': '#2B6E6E',
        'mg-triceps': '#8A6A1E',
        'mg-abs': '#4A5A8A',
        'mg-forearms': '#8A5A6B',
        'mg-other': '#5B6B78',
      };
      const colors = filtered.map(g => MG_PALETTE[g.color_token] || '#5B6B78');

      const baseOpts = {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            backgroundColor: 'rgba(11,29,58,0.92)',
            titleColor: '#FFFFFF',
            bodyColor: '#FFFFFF',
            padding: 10,
            cornerRadius: 6,
            callbacks: {
              label: (c) => `${(+c.parsed.y).toFixed(0)} serie`,
            },
          },
        },
        scales: {
          x: { grid: { display: false }, ticks: { color: '#4B5D75', font: { size: 11 } } },
          y: { beginAtZero: true, grid: { color: 'rgba(75,93,117,0.10)' }, ticks: { color: '#4B5D75', font: { size: 11 } } },
        },
      };

      if (this.progUi.chartType === 'histogram') {
        this._progChart = new Chart(ctx, {
          type: 'bar',
          data: {
            labels,
            datasets: [{
              label: 'Serie',
              data,
              backgroundColor: colors.map(c => c + 'cc'),
              borderColor: colors,
              borderWidth: 1,
              borderRadius: 6,
              borderSkipped: false,
              maxBarThickness: 32,
            }],
          },
          options: baseOpts,
        });
      } else {
        this._progChart = new Chart(ctx, {
          type: 'line',
          data: {
            labels,
            datasets: [{
              label: 'Serie',
              data,
              borderColor: '#1E3A5F',
              backgroundColor: 'rgba(30,58,95,0.10)',
              pointBackgroundColor: colors,
              pointBorderColor: '#FFFFFF',
              pointBorderWidth: 1.5,
              pointRadius: 5,
              pointHoverRadius: 7,
              borderWidth: 2.5,
              tension: 0.32,
              fill: true,
            }],
          },
          options: baseOpts,
        });
      }
    },

    _refreshProgChart() {
      if (this.step === 3 && this._progCanvas) {
        this.renderProgChart();
      }
    },

    /* ---- Per-exercise stats drawer (Volume / Carico / Intensità) ---- */
    openExerciseStats(ex) {
      this.exStats.ex = ex;
      this.exStats.metric = 'volume';
      this.exStats.weeksSelected = this.weekNumbers();
      this.exStats.open = true;
      window.panelLock && window.panelLock.acquire();
      this.$nextTick(() => {
        setTimeout(() => this.renderExStatsChart(), 360);
      });
    },

    closeExerciseStats() {
      if (this.exStats.open) window.panelLock && window.panelLock.release();
      this.exStats.open = false;
      if (this._exStatsChart) {
        try { this._exStatsChart.destroy(); } catch (_) { /* ignore */ }
        this._exStatsChart = null;
      }
    },

    setExStatsMetric(m) {
      if (this.exStats.metric === m) return;
      this.exStats.metric = m;
      this.renderExStatsChart();
    },

    toggleExStatsWeek(w) {
      const i = this.exStats.weeksSelected.indexOf(w);
      if (i >= 0) this.exStats.weeksSelected.splice(i, 1);
      else this.exStats.weeksSelected.push(w);
      this.exStats.weeksSelected.sort((a, b) => a - b);
      this.renderExStatsChart();
    },

    selectAllExStatsWeeks() {
      this.exStats.weeksSelected = this.weekNumbers();
      this.renderExStatsChart();
    },

    mountExStatsCanvas(el) {
      this._exStatsCanvas = el;
      if (this.exStats.open) {
        setTimeout(() => this.renderExStatsChart(), 360);
      }
    },

    exStatsColor() {
      return ({
        volume: '#1E3A5F',
        load: '#9C4448',
        intensity: '#8A6A1E',
      })[this.exStats.metric] || '#1E3A5F';
    },

    exStatsMetricLabel() {
      return ({
        volume: 'Volume',
        load: 'Carico',
        intensity: 'Intensità',
      })[this.exStats.metric] || '';
    },

    exStatsUnit() {
      const ex = this.exStats.ex;
      if (this.exStats.metric === 'volume') return 'rip';
      if (this.exStats.metric === 'intensity') return 'RPE';
      // load
      const unit = ex?.load_unit || 'KG';
      if (unit === 'PERCENT_1RM') return '% 1RM';
      if (unit === 'BODYWEIGHT') return 'BW';
      return 'kg';
    },

    exStatsValue(week) {
      const ex = this.exStats.ex;
      if (!ex) return null;
      const cell = (ex.pk && this.progression.computed?.[String(ex.pk)]?.[String(week)]) || {};
      if (this.exStats.metric === 'volume') {
        const sets = parseInt(cell.set_count ?? ex.sets, 10) || 0;
        const reps = this._parseReps(cell.rep_range ?? ex.reps);
        return sets * reps;
      }
      if (this.exStats.metric === 'load') {
        const lv = (cell.load_value !== undefined && cell.load_value !== null) ? cell.load_value : ex.load_value;
        if (lv === null || lv === undefined || lv === '') return null;
        const n = parseFloat(lv);
        return isNaN(n) ? null : n;
      }
      if (this.exStats.metric === 'intensity') {
        const rpe = (cell.rpe !== undefined && cell.rpe !== null) ? cell.rpe : ex.rpe;
        if (rpe === null || rpe === undefined || rpe === '') return null;
        const n = parseFloat(rpe);
        return isNaN(n) ? null : n;
      }
      return null;
    },

    exStatsValueLabel(week) {
      const v = this.exStatsValue(week);
      if (v === null || v === undefined) return '—';
      const unit = this.exStatsUnit();
      const digits = this.exStats.metric === 'load' ? 1 : (this.exStats.metric === 'intensity' ? 1 : 0);
      return `${(+v).toFixed(digits)} ${unit}`;
    },

    renderExStatsChart() {
      if (this._exStatsChart) {
        try { this._exStatsChart.destroy(); } catch (_) { /* ignore */ }
        this._exStatsChart = null;
      }
      const weeks = (this.exStats.weeksSelected || []).slice().sort((a, b) => a - b);
      if (!weeks.length) { this.exStats.hasData = false; return; }
      // Detect "all nulls" case so the UI can show a friendly empty-state instead
      // of an axis-only blank chart.
      const sample = weeks.map(w => this.exStatsValue(w));
      const hasAny = sample.some(v => v !== null && v !== undefined && !(typeof v === 'number' && isNaN(v)));
      this.exStats.hasData = hasAny;
      if (!hasAny) return;
      if (!this._exStatsCanvas || typeof Chart === 'undefined') return;

      // Reset inline sizing so Chart.js manages canvas pixel dims.
      this._exStatsCanvas.removeAttribute('width');
      this._exStatsCanvas.removeAttribute('height');
      this._exStatsCanvas.style.width = '';
      this._exStatsCanvas.style.height = '';

      const color = this.exStatsColor();
      const labels = weeks.map(w => 'S' + w);
      const data = weeks.map(w => this.exStatsValue(w));
      const unit = this.exStatsUnit();
      const digits = this.exStats.metric === 'load' ? 1 : (this.exStats.metric === 'intensity' ? 1 : 0);

      const ctx = this._exStatsCanvas.getContext('2d');
      this._exStatsChart = new Chart(ctx, {
        type: 'line',
        data: {
          labels,
          datasets: [{
            label: this.exStatsMetricLabel(),
            data,
            borderColor: color,
            backgroundColor: color + '22',
            pointBackgroundColor: color,
            pointBorderColor: '#FFFFFF',
            pointBorderWidth: 1.5,
            pointRadius: 6,
            pointHoverRadius: 8,
            borderWidth: 2.5,
            tension: 0.32,
            fill: true,
            spanGaps: true,
          }],
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          animation: false,
          plugins: {
            legend: { display: false },
            tooltip: {
              backgroundColor: 'rgba(11,29,58,0.92)',
              titleColor: '#FFFFFF',
              bodyColor: '#FFFFFF',
              padding: 10,
              cornerRadius: 6,
              callbacks: {
                label: (c) => {
                  const v = c.parsed?.y;
                  if (v === null || v === undefined) return '—';
                  return `${(+v).toFixed(digits)} ${unit}`;
                },
              },
            },
          },
          scales: {
            x: { grid: { display: false }, ticks: { color: '#4B5D75', font: { size: 11 } } },
            y: {
              beginAtZero: this.exStats.metric !== 'intensity',
              grid: { color: 'rgba(75,93,117,0.12)' },
              ticks: { color: '#4B5D75', font: { size: 11 } },
            },
          },
        },
      });
    },

    // ---- Save / autosave ----
    markDirty() {
      this.saveState = 'idle';
      if (this.saveTimer) clearTimeout(this.saveTimer);
      this.saveTimer = setTimeout(() => this.saveDraft(), 1500);
      this._refreshVolumeIfOpen();
    },

    async saveDraft(showToast = false) {
      // Prevent saving empty plans
      if (!this.canAdvanceStep2()) {
        if (showToast) this._showToast('Aggiungi almeno un esercizio', 'error');
        return;
      }

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
        folder_id: this.plan.folder_id || null,
        plan_kind: this.plan.plan_kind || 'WEEKLY',
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
            coach_notes: ex.coach_notes || ex.notes || '',
            execution_type: ex.execution_type || 'REPETITION',
            rpe: ex.rpe,
            rir: ex.rir,
            tempo: ex.tempo || '',
            superset_group_id: ex.superset_group_id,
            set_details: Array.isArray(ex.set_details) ? ex.set_details : [],
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
      if (this.plan && this.plan.id) params.set('exclude_plan_id', this.plan.id);
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
      // Prevent finalizing empty plans
      if (!this.canAdvanceStep2()) {
        this.errors.finalize = 'Aggiungi almeno un esercizio prima di assegnare.';
        return null;
      }

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
      // For WEEKLY plans the coach picks a duration (weeks or months) — the
      // server owns the unit -> end_date math. For PROGRAM plans the duration
      // is fixed by the progression and sent as weeks like before.
      const isProgram = this.plan.plan_kind === 'PROGRAM';
      if (isProgram) {
        if (!this.plan.duration_weeks || this.plan.duration_weeks < 1) {
          this.errors.assign = 'Durata progressione non valida.';
          return;
        }
      } else if (!this.assignDurationValue || this.assignDurationValue < 1) {
        this.errors.assign = 'Seleziona per quanto tempo far seguire la scheda.';
        return;
      }
      const conflicts = this.conflictingClients();
      if (conflicts.length > 0 && !this.overwriteConfirmed) {
        this.errors.assign = 'Conferma la sovrascrittura delle schede attive.';
        return;
      }
      // Ensure latest state on server
      await this.saveDraft();
      const d = await this._finalize({
        action: 'assign',
        client_ids: this.selectedClientIds,
        duration_value: isProgram ? null : this.assignDurationValue,
        duration_unit: isProgram ? null : this.assignDurationUnit,
        overwrite: conflicts.length > 0 && this.overwriteConfirmed,
      });
      if (d) {
        this._showToast('Scheda assegnata!');
        setTimeout(() => { window.location.href = d.redirect_url || this.urls.list; }, 1200);
      }
    },

    async doSaveDraft() {
      await this.saveDraft();
      const d = await this._finalize({ action: 'draft' });
      if (d) {
        this._showToast('Salvata come bozza');
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

    // ---- Step 4 recap helpers ----
    folderName() {
      const fid = this.plan?.folder_id;
      if (!fid) return '';
      const f = (this.foldersCatalog || []).find(x => x.id === fid);
      return f ? f.name : '';
    },

    toggleRecapDay(id) {
      // Mutate in place: replacing the whole object (as `{...spread}` did)
      // makes Alpine re-check recapDaysOpen[...] on every day block, not just
      // this one, which is what caused the open/close lag with several days.
      this.recapDaysOpen[id] = !this.recapDaysOpen[id];
    },
    allRecapDaysOpen() {
      const days = this.plan?.days || [];
      if (days.length === 0) return false;
      return days.every(d => !!this.recapDaysOpen[d.local_id]);
    },
    toggleAllRecapDays() {
      const open = !this.allRecapDaysOpen();
      (this.plan?.days || []).forEach(d => { this.recapDaysOpen[d.local_id] = open; });
    },

    formatRecovery(secs) {
      const s = parseInt(secs) || 0;
      if (s >= 60) {
        const m = Math.floor(s / 60);
        const r = s % 60;
        return r ? `${m}′${r}″` : `${m}′`;
      }
      return `${s}″`;
    },
    executionLabel(t) {
      return ({
        REPETITION: 'Ripetizioni',
        TIME: 'A tempo',
        AMRAP: 'AMRAP',
        EMOM: 'EMOM',
        ISOMETRIC: 'Isometrico',
      })[t] || t;
    },

    visibleClients() {
      // Selected clients always visible. Otherwise top 5 of current results.
      const list = this.clientsList || [];
      const selected = list.filter(c => this.selectedClientIds.includes(c.id));
      const others = list.filter(c => !this.selectedClientIds.includes(c.id));
      const top = others.slice(0, Math.max(0, 5 - selected.length));
      return [...selected, ...top];
    },
    clientInitials(name) {
      return (name || '').split(/\s+/).filter(Boolean).slice(0, 2).map(s => s[0]).join('').toUpperCase() || '?';
    },
    conflictingClients() {
      return (this.clientsList || []).filter(c =>
        this.selectedClientIds.includes(c.id) && c.active_assignment
      );
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
      // Legacy ProgressionRule objects are no longer used by the redesigned Step 3
      // grid (per-cell WeeklyOverride only). Drop them client-side so the next
      // saveDraft diff deletes them server-side.
      this.progression.rules = [];
      this.progression.overrides = (srvProg.overrides || []).map(o => ({ ...o }));
      this.progression.computed = srvProg.computed || {};
      this.progression.conflicts = [];
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
      // Identity match: prefer server pk; fall back to client _local_id only when
      // BOTH sides carry one. Without the truthy guards, two server-loaded rules
      // would compare `undefined === undefined` and the map() would overwrite
      // every sibling with the edited draft.
      const isSame = (x) => {
        if (r.id != null && x.id != null) return x.id === r.id;
        if (r._local_id && x._local_id) return x._local_id === r._local_id;
        return false;
      };
      if (this.progression.rules.some(isSame)) {
        this.progression.rules = this.progression.rules.map(x => isSame(x) ? { ...r } : x);
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

    async removeRule(r) {
      if (!await window.alConfirm({ icon: 'ph-trash', title: 'Rimuovere la\nprogressione?', subtitle: 'I valori delle settimane saranno ricalcolati.', confirmLabel: 'Sì, rimuovi' })) return;
      const isSame = (x) => {
        if (r.id != null && x.id != null) return x.id === r.id;
        if (r._local_id && x._local_id) return x._local_id === r._local_id;
        return false;
      };
      this.progression.rules = this.progression.rules.filter(x => !isSame(x));
      this.markDirty();
    },

    /* ====================================================================
       Step 3 — Per-day progression grid (redesigned)
       ==================================================================== */
    _currentDay() {
      return this.plan?.days?.[this.progGrid.dayIdx] || null;
    },

    setProgGridDay(idx) {
      if (idx < 0 || idx >= this.plan.days.length) return;
      this.progGrid.dayIdx = idx;
      this.progGrid.windowStart = 1;
      this.loadProgGrid();
    },

    progGridVisibleWeeks() {
      const total = parseInt(this.plan?.duration_weeks, 10) || 1;
      const size = Math.min(this.progGrid.windowSize, total);
      const start = Math.max(1, Math.min(this.progGrid.windowStart, total - size + 1));
      const out = [];
      for (let i = 0; i < size; i++) out.push(start + i);
      return out;
    },

    canShiftProgGrid(dir) {
      const total = parseInt(this.plan?.duration_weeks, 10) || 1;
      const size = Math.min(this.progGrid.windowSize, total);
      if (dir < 0) return this.progGrid.windowStart > 1;
      return this.progGrid.windowStart + size <= total;
    },

    shiftProgGrid(dir) {
      if (!this.canShiftProgGrid(dir)) return;
      this.progGrid.windowStart += dir;
      this.progGrid.slideDir = dir;
      // Reset slide marker after animation finishes so subsequent re-renders
      // (eg field edits inside the grid) don't replay the slide.
      setTimeout(() => { this.progGrid.slideDir = 0; }, 600);
    },

    async loadProgGrid() {
      const day = this._currentDay();
      if (!day || !day.pk || !this.plan.id) {
        // Day not persisted yet — saveDraft first so we have pks.
        if (this.plan.id) await this.saveDraft();
        const d2 = this._currentDay();
        if (!d2 || !d2.pk) {
          this.progGrid.exercises = [];
          this.progGrid.cells = {};
          return;
        }
      }
      const dayPk = this._currentDay().pk;
      this.progGrid.loading = true;
      try {
        const r = await fetch(`/api/allenamenti/${this.plan.id}/progression/day/${dayPk}/grid/`, { credentials: 'same-origin' });
        if (!r.ok) throw new Error('grid fetch failed: ' + r.status);
        const d = await r.json();
        const grid = d.grid || {};
        this.progGrid.exercises = grid.exercises || [];
        this.progGrid.cells = grid.cells || {};
      } catch (e) {
        console.error('[progGrid] load failed', e);
        this.progGrid.exercises = [];
        this.progGrid.cells = {};
      } finally {
        this.progGrid.loading = false;
      }
    },

    isCellExpanded(ex) {
      return !!this.progGrid.expanded[ex.pk];
    },

    toggleCellExpanded(ex) {
      const k = ex.pk;
      this.progGrid.expanded = { ...this.progGrid.expanded, [k]: !this.progGrid.expanded[k] };
    },

    // Which intensity field the exercise uses — RIR or RPE (never both).
    rpeRirMetricFor(ex) {
      const r = ex.base?.rir;
      return (r !== null && r !== undefined && r !== '') ? 'rir' : 'rpe';
    },

    // All 6 progression fields, always shown (no "+" expand): top row
    // Serie/Reps/Carico, bottom row Recupero/RIR-or-RPE/TUT.
    cellFields(ex) {
      const rr = this.rpeRirMetricFor(ex);
      return [
        { metric: 'set_count',        label: 'Serie',   type: 'number', step: '1',    min: 1 },
        { metric: 'rep_range',        label: 'Reps',    type: 'text' },
        { metric: 'load_value',       label: 'Carico',  type: 'number', step: '0.25', min: 0 },
        { metric: 'recovery_seconds', label: 'Rec (s)', type: 'number', step: '5',    min: 0 },
        { metric: rr,                 label: rr === 'rir' ? 'RIR' : 'RPE', type: 'number',
          step: rr === 'rir' ? '1' : '0.5', min: 0 },
        { metric: 'tempo',            label: 'TUT',     type: 'text' },
      ];
    },

    progGridExercisesAtWeek(week) {
      return (this.progGrid.exercises || [])
        .filter(ex => {
          const starts = ex.starts_at_week || 1;
          const ends = ex.ends_at_week;  // null = no upper bound
          const inactive = Array.isArray(ex.inactive_weeks) ? ex.inactive_weeks : [];
          if (week < starts) return false;
          if (ends != null && week > ends) return false;
          if (inactive.includes(week)) return false;
          return true;
        })
        .map(ex => ({
          pk: ex.id,
          local_id: 'srv-' + ex.id,
          exercise_id: ex.exercise_id,
          exercise_name: ex.name,
          starts_at_week: ex.starts_at_week || 1,
          ends_at_week: ex.ends_at_week,
          inactive_weeks: ex.inactive_weeks || [],
          base: ex.base || {},
        }));
    },

    _cellFor(ex, week, metric) {
      const cellsByEx = this.progGrid.cells || {};
      const exId = ex.pk;
      return cellsByEx?.[exId]?.[week]?.[metric] || null;
    },

    cellFieldRawValue(ex, week, metric) {
      const cell = this._cellFor(ex, week, metric);
      if (!cell) return '';
      const v = cell.value;
      return (v === null || v === undefined) ? '' : String(v);
    },

    cellFieldPlaceholder(ex, week, metric) {
      const base = ex.base?.[metric];
      return (base === null || base === undefined || base === '') ? '—' : String(base);
    },

    cellFieldClass(ex, week, metric) {
      const cell = this._cellFor(ex, week, metric);
      if (!cell) return 'is-inherited';
      if (cell.source === 'override') return 'is-override';
      if (cell.source === 'inherit') return 'is-inherited is-from-override';
      return 'is-inherited';
    },

    cellFieldHint(ex, week, metric) {
      const cell = this._cellFor(ex, week, metric);
      if (!cell) return '';
      if (cell.source === 'override') return 'Valore impostato in questa settimana';
      if (cell.source === 'inherit') return 'Ereditato da S' + cell.override_week;
      return 'Valore base dall\'esercizio';
    },

    // Week 1 is edited directly on WorkoutExercise (bidirectional with the
    // builder), so Step 2's separate in-memory copy needs to be patched too —
    // it's a distinct array from progGrid.exercises, not a shared reference.
    _syncBaseFieldToBuilder(exPk, metric, value) {
      if (!exPk) return;
      const fieldMap = { set_count: 'sets', rep_range: 'reps' };
      const field = fieldMap[metric] || metric;
      for (const day of this.plan.days || []) {
        const match = (day.exercises || []).find(e => e.pk === exPk);
        if (match) { match[field] = value; return; }
      }
    },

    async commitCellEdit(ex, week, metric, raw, evt) {
      if (evt && evt.target) evt.target.classList.remove('is-focused');
      const current = this._cellFor(ex, week, metric);
      const currentVal = current ? current.value : ex.base?.[metric];
      const trimmed = raw == null ? '' : String(raw).trim();

      // Coerce numeric inputs.
      const numericMetrics = ['set_count', 'load_value', 'rpe', 'rir', 'recovery_seconds'];
      let payloadValue = trimmed;
      if (trimmed === '') {
        payloadValue = null;
      } else if (numericMetrics.includes(metric)) {
        const n = parseFloat(trimmed);
        if (isNaN(n)) {
          this._showToast('Valore non valido');
          await this.loadProgGrid();
          return;
        }
        payloadValue = (metric === 'set_count' || metric === 'rir' || metric === 'recovery_seconds') ? Math.round(n) : n;
      }

      // No-op if same as current effective value.
      const a = (currentVal === null || currentVal === undefined) ? null : String(currentVal);
      const b = (payloadValue === null || payloadValue === undefined) ? null : String(payloadValue);
      if (a === b && (!current || current.source !== 'override')) return;

      try {
        const r = await fetch(`/api/allenamenti/${this.plan.id}/progression/cell/`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this.getCsrf() },
          body: JSON.stringify({
            workout_exercise_id: ex.pk,
            week_number: week,
            metric,
            value: payloadValue,
            clear: payloadValue === null,
          }),
        });
        if (!r.ok) {
          const d = await r.json().catch(() => ({}));
          this._showToast(d.error || 'Errore aggiornamento');
        } else {
          const d = await r.json().catch(() => ({}));
          if (d.computed) {
            this.progression.computed = d.computed;
            this._computeProgVolume();
            this._refreshProgChart();
          }
          if (week === 1) this._syncBaseFieldToBuilder(ex.pk, metric, payloadValue);
        }
      } catch (_) {
        this._showToast('Errore di rete');
      }
      await this.loadProgGrid();
    },

    /* ---- Per-set differentiation inside the progression grid ----
       set_details is forward-filled like any other metric: an override at a
       week inherits to later weeks until the next override. Week 1 writes
       straight to the builder's WorkoutExercise.set_details (bidirectional). */
    cellSetDetails(ex, week) {
      const c = this._cellFor(ex, week, 'set_details');
      const v = c && c.value;
      return Array.isArray(v) ? v : [];
    },
    progSetCount(ex, week) {
      const c = this._cellFor(ex, week, 'set_count');
      const raw = (c && c.value != null) ? c.value : ex.base?.set_count;
      const n = parseInt(raw, 10);
      return isNaN(n) ? 0 : Math.max(0, Math.min(n, 12));
    },
    setDetailValue(ex, week, setIdx, field) {
      const rows = this.cellSetDetails(ex, week);
      const r = rows[setIdx];
      const v = r ? r[field] : null;
      return (v === null || v === undefined) ? '' : String(v);
    },
    async setDetailEdit(ex, week, setIdx, field, rawValue) {
      const count = this.progSetCount(ex, week);
      let rows = this.cellSetDetails(ex, week).map(r => ({ ...r }));
      while (rows.length < count) rows.push({});
      rows = rows.slice(0, Math.max(count, rows.length));
      const v = (rawValue === '' || rawValue == null) ? null : rawValue;
      rows[setIdx] = { ...rows[setIdx], [field]: v };
      // Drop trailing all-empty rows; if nothing left, clear the override.
      const isEmpty = (r) => Object.values(r).every(x => x === null || x === undefined || x === '');
      if (rows.every(isEmpty)) rows = [];
      await this.commitSetDetails(ex, week, rows);
    },
    async commitSetDetails(ex, week, rows) {
      if (!this.plan?.id) return;
      try {
        const r = await fetch(`/api/allenamenti/${this.plan.id}/progression/cell/`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this.getCsrf() },
          body: JSON.stringify({
            workout_exercise_id: ex.pk,
            week_number: week,
            metric: 'set_details',
            value: rows.length ? rows : null,
            clear: rows.length === 0,
          }),
        });
        if (!r.ok) {
          const d = await r.json().catch(() => ({}));
          this._showToast(d.error || 'Errore aggiornamento serie');
        } else if (week === 1) {
          this._syncBaseFieldToBuilder(ex.pk, 'set_details', rows);
        }
      } catch (_) {
        this._showToast('Errore di rete');
      }
      await this.loadProgGrid();
    },

    /* ---- Delete cell (per-week or forward) ---- */
    openDeleteCellConfirm(ex, week) {
      this.deleteUi.exId = ex.pk;
      this.deleteUi.exName = ex.exercise_name || '';
      this.deleteUi.week = week;
      this.deleteUi.open = true;
      window.panelLock && window.panelLock.acquire();
    },

    closeDeleteCellConfirm() {
      if (this.deleteUi.open) window.panelLock && window.panelLock.release();
      this.deleteUi.open = false;
    },

    async confirmDeleteCell(mode) {
      const exId = this.deleteUi.exId;
      const week = this.deleteUi.week;
      this.closeDeleteCellConfirm();
      if (!exId || !this.plan?.id) return;
      try {
        const r = await fetch(`/api/allenamenti/${this.plan.id}/progression/exercise/${exId}/delete-cell/`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this.getCsrf() },
          body: JSON.stringify({ mode, week_number: week }),
        });
        if (!r.ok) {
          const d = await r.json().catch(() => ({}));
          this._showToast(d.error || 'Errore cancellazione');
          return;
        }
      } catch (_) {
        this._showToast('Errore di rete');
        return;
      }
      await this.loadProgGrid();
    },

    /* ---- Add exercise at week ---- */
    openAddExerciseForWeek(week) {
      this.addExUi.open = true;
      this.addExUi.week = week;
      this.addExUi.dayIdx = this.progGrid.dayIdx;
      this.addExUi.query = '';
      this.addExUi.results = [];
      window.panelLock && window.panelLock.acquire();
      this.searchAddExercises();
    },

    closeAddExerciseAtWeek() {
      if (this.addExUi.open) window.panelLock && window.panelLock.release();
      this.addExUi.open = false;
    },

    async searchAddExercises() {
      this.addExUi.loading = true;
      const params = new URLSearchParams();
      if (this.addExUi.query) params.set('q', this.addExUi.query);
      try {
        const r = await fetch(`${this.urls.search_exercises}?${params.toString()}`);
        this.addExUi.results = (await r.json()).slice(0, 20);
      } catch (_) {
        this.addExUi.results = [];
      } finally {
        this.addExUi.loading = false;
      }
    },

    async confirmAddExerciseAtWeek(opt) {
      const day = this._currentDay();
      if (!day || !day.pk) {
        this._showToast('Salva la bozza prima di aggiungere esercizi.');
        return;
      }
      try {
        const r = await fetch(`/api/allenamenti/${this.plan.id}/progression/add-exercise/`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this.getCsrf() },
          body: JSON.stringify({
            workout_day_id: day.pk,
            exercise_id: opt.id,
            starts_at_week: this.addExUi.week,
          }),
        });
        if (!r.ok) {
          const d = await r.json().catch(() => ({}));
          this._showToast(d.error || 'Errore aggiunta');
          return;
        }
        this.closeAddExerciseAtWeek();
        await this.loadProgGrid();
      } catch (_) {
        this._showToast('Errore di rete');
      }
    },
  }));
});
