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

    library: { query: '', muscle: '', equipment: '', items: [], loading: false },
    filters: { muscles: [], equipment: [] },

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
    assignStart: '',
    assignEnd: '',
    finalizing: false,

    errors: { step1: '', step2: '', assign: '', finalize: '' },
    toast: '',

    urls: window.WIZARD_URLS,

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
        status: init.status || 'DRAFT',
        last_step: init.last_step || 1,
        days: this._materializeDays(init.days || []),
      };

      // Resume to last_step if existing draft
      if (this.plan.id && this.plan.last_step) {
        this.step = Math.max(1, Math.min(3, this.plan.last_step));
      } else {
        this.step = 1;
      }
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
          primary_muscles: ex.primary_muscles || [],
          secondary_muscles: ex.secondary_muscles || [],
          equipment_groups: ex.equipment_groups || [],
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
    stepName(s) { return ({1:'Informazioni', 2:'Builder', 3:'Riepilogo & Assegna'})[s]; },

    canAdvanceStep1() {
      return this.plan && this.plan.title.trim().length > 0 && !!this.plan.frequency_per_week;
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
        this.step = 3;
        this.plan.last_step = 3;
        this.saveDraft();
        return;
      }
    },

    goPrev() {
      if (this.step > 1) {
        this.step -= 1;
        if (this.step === 2) this.$nextTick(() => this.bindSortable());
      }
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
        primary_muscles: libEx.primary_muscles || [],
        secondary_muscles: libEx.secondary_muscles || [],
        equipment_groups: libEx.equipment_groups || [],
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
          (ex.primary_muscles || []).forEach(m => {
            map[m] = (map[m] || 0) + baseVol;
          });
          (ex.secondary_muscles || []).forEach(m => {
            map[m] = (map[m] || 0) + baseVol * 0.5;
          });
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
        last_step: this.step,
        days: this.plan.days.map((d, di) => ({
          pk: d.pk,
          order: di + 1,
          name: d.name,
          exercises: d.exercises.map((ex, ei) => ({
            pk: ex.pk,
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
      if (!this.assignStart) {
        this.errors.assign = 'Data inizio obbligatoria.';
        return;
      }
      // Ensure latest state on server
      await this.saveDraft();
      const d = await this._finalize({
        action: 'assign',
        client_ids: this.selectedClientIds,
        start_date: this.assignStart,
        end_date: this.assignEnd || null,
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
  }));
});
