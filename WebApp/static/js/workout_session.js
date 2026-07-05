function sessionRunner() {
  return {
    sessionId: null,
    startError: '',
    exercises: [],

    planTitle: window.SESSION_INIT.plan_title || '',
    planGoal: window.SESSION_INIT.plan_goal || '',
    placeText: window.SESSION_INIT.place || 'Palestra',
    weekIndex: window.SESSION_INIT.week_index || 1,
    dayOrder: window.SESSION_INIT.day_order || 1,

    // expanded[exId] = bool
    expanded: {},
    activeExId: null,

    // localValues[exId+'-'+setN] = { reps_done, load_used, rpe, notes }
    localValues: {},
    // doneSets[exId] = [setN1, setN2,...]
    doneSets: {},
    // extraSets[exId] = number of extra sets added by user (above ex.sets)
    extraSets: {},
    // exerciseNotes[exId] = string
    exerciseNotes: {},
    notesOpen: {},
    // substituted[exId] = { id, name } (alternative or free pick)
    substituted: {},
    // removed[exId] = true (session-only, restorable)
    removed: {},
    // Exercise picker (add / substitute). Added exercises get id 'add-<catalog id>'.
    pickerModal: {
      open: false, mode: 'add', forEx: null,
      q: '', group: '', groups: [], results: [],
      similar: [], exploreAll: false, loading: false,
    },
    removeModal: { open: false, ex: null },
    _pickerT: null,

    // timers[exId] = { active, paused, sec, _h }
    timers: {},

    warmupDone: false,

    elapsed: 0,
    _tick: null,

    confirmStop: false,
    finishModalOpen: false,
    finalNotes: '',
    finalizing: false,
    uploaded: [],
    uploadingCount: 0,

    instructionsModal: { open: false, ex: null },
    substituteModal: { open: false, ex: null },

    urls: window.SESSION_INIT.urls,

    async init() {
      console.log('[sessionRunner] init() called', { SESSION_INIT: window.SESSION_INIT });
      this.exercises = window.SESSION_INIT.exercises || [];
      console.log('[sessionRunner] exercises loaded:', this.exercises.length);

      // Pre-initialize per-exercise reactive maps so Alpine tracks every key
      const expanded = {};
      const notesOpen = {};
      const extraSets = {};
      const exerciseNotes = {};
      const doneSets = {};
      const timers = {};
      for (const ex of this.exercises) {
        expanded[ex.id] = false;
        notesOpen[ex.id] = false;
        extraSets[ex.id] = 0;
        exerciseNotes[ex.id] = '';
        doneSets[ex.id] = [];
        timers[ex.id] = { active: false, paused: false, sec: 0, _h: null };
      }
      if (this.exercises.length) {
        expanded[this.exercises[0].id] = true;
        this.activeExId = this.exercises[0].id;
      }
      this.expanded = expanded;
      this.notesOpen = notesOpen;
      this.extraSets = extraSets;
      this.exerciseNotes = exerciseNotes;
      this.doneSets = doneSets;
      this.timers = timers;

      try {
        const r = await fetch(this.urls.start, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this._csrf() },
          body: JSON.stringify({
            assignment_id: window.SESSION_INIT.assignment_id,
            day_id: window.SESSION_INIT.day_id,
          }),
        });
        if (!r.ok) throw new Error('start failed');
        const d = await r.json();
        this.sessionId = d.session_id;
        this._hydrateFromServer(d);
      } catch (e) {
        this.startError = 'Impossibile avviare la sessione. Riprova.';
        return;
      }

      this._tick = setInterval(() => { this.elapsed += 1; }, 1000);
      this._flushPending();
      window.addEventListener('online', () => this._flushPending());
    },

    _hydrateFromServer(d) {
      // Session-only overrides first, so added exercises exist before their sets
      const ov = d.overrides || {};
      const newRemoved = {};
      for (const id of (ov.removed || [])) newRemoved[id] = true;
      this.removed = newRemoved;
      for (const se of (d.exercises || [])) {
        if (se.added && se.exercise_id) {
          this._appendAdded({ id: se.exercise_id, name: se.name, video_url: se.video_url || '' });
        }
      }

      // Restore prior progress on reload / mid-session resume
      const sets = d.sets_logged || [];
      const newDone = { ...this.doneSets };
      const newLocal = { ...this.localValues };
      const newExtra = { ...this.extraSets };
      const newSubst = { ...this.substituted };
      for (const se of (d.exercises || [])) {
        if (se.workout_exercise_id && se.substituted_with) {
          newSubst[se.workout_exercise_id] = se.substituted_with;
        }
      }
      for (const s of sets) {
        const exId = s.workout_exercise_id ?? ('add-' + s.exercise_id);
        const k = exId + '-' + s.set_number;
        newLocal[k] = {
          reps_done: s.reps_done,
          load_used: s.load_used,
          rpe: s.rpe,
          notes: s.notes || '',
        };
        if (s.completed) {
          const arr = newDone[exId] || [];
          if (!arr.includes(s.set_number)) {
            newDone[exId] = [...arr, s.set_number].sort((a, b) => a - b);
          }
        }
        const ex = this.exercises.find(e => e.id === exId);
        if (ex && s.set_number > (ex.sets || 0)) {
          newExtra[exId] = Math.max(newExtra[exId] || 0, s.set_number - (ex.sets || 0));
        }
        if (s.exercise_substituted && s.actual_exercise_id && ex && ex.alternative_exercise) {
          newSubst[exId] = ex.alternative_exercise;
        }
      }
      this.doneSets = newDone;
      this.localValues = newLocal;
      this.extraSets = newExtra;
      this.substituted = newSubst;
      const notesMap = d.exercise_notes || {};
      const newNotes = { ...this.exerciseNotes };
      for (const [id, v] of Object.entries(notesMap)) {
        newNotes[Number(id)] = v || '';
      }
      this.exerciseNotes = newNotes;
      // Auto-expand first non-complete exercise
      for (const ex of this.exercises) {
        if (!this.isExComplete(ex) && !this.removed[ex.id]) {
          this.expanded[ex.id] = true;
          this.activeExId = ex.id;
          break;
        }
      }
    },

    // ---- Session-only overrides (add / remove / substitute) ----
    _appendAdded(item) {
      const id = 'add-' + item.id;
      if (this.exercises.some(e => e.id === id)) return;
      this.exercises.push({
        id,
        exercise_id: item.id,
        exercise_catalog_id: item.id,
        name: item.name,
        sets: 3,
        reps: '10',
        load_value: null,
        load_unit: 'KG',
        recovery_seconds: 90,
        notes: '',
        set_details: [],
        video_url: item.video_url || '',
        alternative_exercise: null,
        added: true,
      });
      this.expanded[id] = false;
      this.notesOpen[id] = false;
      this.extraSets[id] = 0;
      this.exerciseNotes[id] = '';
      this.doneSets[id] = this.doneSets[id] || [];
      this.timers[id] = { active: false, paused: false, sec: 0, _h: null };
    },

    async saveOverrides() {
      if (!this.sessionId) return;
      const substituted = {};
      for (const [weId, sub] of Object.entries(this.substituted)) {
        if (!String(weId).startsWith('add-')) substituted[weId] = sub.id;
      }
      const payload = {
        removed: Object.keys(this.removed).filter(k => this.removed[k] && !String(k).startsWith('add-')).map(Number),
        substituted,
        added: this.exercises.filter(e => e.added).map((e, i) => ({ exercise_id: e.exercise_id, order: i })),
      };
      try {
        await fetch(this.urls.overrides_tpl.replace('__SID__', this.sessionId), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this._csrf() },
          body: JSON.stringify(payload),
        });
      } catch (_) {}
    },

    askRemove(ex) {
      this.removeModal = { open: true, ex };
    },

    confirmRemove() {
      const ex = this.removeModal.ex;
      this.removeModal.open = false;
      if (!ex) return;
      if (ex.added) {
        this.exercises = this.exercises.filter(e => e.id !== ex.id);
      } else {
        this.removed = { ...this.removed, [ex.id]: true };
        this.expanded[ex.id] = false;
      }
      this.saveOverrides();
    },

    restoreExercise(ex) {
      const next = { ...this.removed };
      delete next[ex.id];
      this.removed = next;
      this.saveOverrides();
    },

    // ---- Exercise picker (add / substitute) ----
    openAddPicker() {
      this.pickerModal = {
        open: true, mode: 'add', forEx: null,
        q: '', group: '', groups: [], results: [],
        similar: [], exploreAll: true, loading: true,
      };
      this._pickerFetch(true);
    },

    async openSubstitutePicker(ex) {
      this.pickerModal = {
        open: true, mode: 'substitute', forEx: ex,
        q: '', group: '', groups: [], results: [],
        similar: [], exploreAll: false, loading: true,
      };
      try {
        const catId = ex.exercise_catalog_id || ex.exercise_id;
        const r = await fetch(this.urls.search + '?similar_to=' + catId + '&limit=30');
        const d = await r.json();
        this.pickerModal.similar = d.results || [];
      } catch (_) {}
      this.pickerModal.loading = false;
    },

    exploreAllExercises() {
      this.pickerModal.exploreAll = true;
      this.pickerModal.loading = true;
      this._pickerFetch(true);
    },

    pickerInput() {
      clearTimeout(this._pickerT);
      this._pickerT = setTimeout(() => this._pickerFetch(), 250);
    },

    pickerGroup(slug) {
      this.pickerModal.group = this.pickerModal.group === slug ? '' : slug;
      this._pickerFetch();
    },

    async _pickerFetch(withGroups = false) {
      const p = this.pickerModal;
      const params = new URLSearchParams();
      if (p.q) params.set('q', p.q);
      if (p.group) params.set('muscle_group', p.group);
      if (withGroups || !p.groups.length) params.set('include_groups', '1');
      params.set('limit', '30');
      try {
        const r = await fetch(this.urls.search + '?' + params.toString());
        const d = await r.json();
        p.results = d.results || [];
        if (d.muscle_groups) p.groups = d.muscle_groups;
      } catch (_) {}
      p.loading = false;
    },

    choosePicked(item) {
      const p = this.pickerModal;
      if (p.mode === 'add') {
        this._appendAdded(item);
        this.expanded['add-' + item.id] = true;
      } else if (p.forEx) {
        this.substituted = { ...this.substituted, [p.forEx.id]: { id: item.id, name: item.name } };
      }
      p.open = false;
      this.saveOverrides();
    },

    _csrf() {
      return window.csrfToken();
    },

    _key(exId, setN) { return exId + '-' + setN; },

    // ---- Display ----
    exerciseDisplayName(ex) {
      if (!ex) return '';
      const sub = this.substituted[ex.id];
      return sub ? sub.name : ex.name;
    },

    nextExercise() {
      // First exercise that has sets remaining (removed ones don't count)
      for (const ex of this.exercises) {
        if (!this.isExComplete(ex) && !this.removed[ex.id]) return ex;
      }
      return null;
    },

    activeExercises() {
      return this.exercises.filter(ex => !this.removed[ex.id]);
    },

    showInstructions(ex) {
      this.instructionsModal = { open: true, ex };
    },

    // ---- Expand/collapse ----
    toggleExpand(exId) {
      this.expanded[exId] = !this.expanded[exId];
      if (this.expanded[exId]) this.activeExId = exId;
    },

    // ---- Sets ----
    totalSetsFor(ex) {
      return ex.sets + (this.extraSets[ex.id] || 0);
    },

    setValue(exId, setN, field, ex) {
      const k = this._key(exId, setN);
      const v = this.localValues[k];
      if (v && v[field] !== undefined && v[field] !== null && v[field] !== '') return v[field];
      // Fallback to prescription (each set independent)
      if (field === 'reps_done') {
        const m = String(ex.reps || '').match(/(\d+)/);
        return m ? parseInt(m[1]) : '';
      }
      if (field === 'load_used') return ex.load_value ?? '';
      if (field === 'rpe') return 7;
      return '';
    },

    updateLocal(exId, setN, field, value) {
      const k = this._key(exId, setN);
      if (!this.localValues[k]) this.localValues[k] = {};
      const num = ['reps_done', 'load_used', 'rpe'].includes(field);
      let v = num ? (value === '' ? null : parseFloat(value)) : value;
      if (field === 'rpe' && v !== null) v = Math.min(10, Math.max(1, v));
      this.localValues[k][field] = v;
    },

    isSetDone(exId, setN) {
      const arr = this.doneSets[exId] || [];
      return arr.includes(setN);
    },

    isSetActive(ex, setN) {
      // active = first not-done set
      for (let i = 1; i <= this.totalSetsFor(ex); i++) {
        if (!this.isSetDone(ex.id, i)) return i === setN;
      }
      return false;
    },

    isExComplete(ex) {
      const arr = this.doneSets[ex.id] || [];
      return arr.length >= this.totalSetsFor(ex);
    },

    addExtraSet(exId) {
      this.extraSets[exId] = (this.extraSets[exId] || 0) + 1;
    },

    // ---- Stats ----
    get completedExCount() {
      return this.activeExercises().filter(ex => this.isExComplete(ex)).length;
    },

    get totalDoneSets() {
      return Object.values(this.doneSets).reduce((a, b) => a + b.length, 0);
    },

    get progressPct() {
      const tot = this.activeExercises().reduce((a, e) => a + this.totalSetsFor(e), 0);
      if (!tot) return 0;
      return Math.min(100, Math.round((this.totalDoneSets / tot) * 100));
    },

    get avgRpe() {
      const all = [];
      Object.entries(this.localValues).forEach(([k, v]) => {
        // exId may be 'add-<id>' — split on the LAST dash only
        const i = k.lastIndexOf('-');
        const exId = k.slice(0, i);
        const setN = Number(k.slice(i + 1));
        if (this.isSetDone(exId, setN) && v && v.rpe) all.push(v.rpe);
      });
      if (!all.length) return null;
      return (all.reduce((a, b) => a + b, 0) / all.length).toFixed(1);
    },

    formatTime(sec) {
      sec = Math.max(0, Math.floor(sec || 0));
      const m = Math.floor(sec / 60);
      const s = sec % 60;
      return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
    },

    // ---- Complete set + start timer ----
    async completeSetAndStartTimer(ex, setNum) {
      await this._saveSet(ex, setNum, true);
      this._startTimer(ex.id, ex.recovery_seconds || 90);
    },

    async _saveSet(ex, setNum, completed) {
      const k = this._key(ex.id, setNum);
      const v = this.localValues[k] || {};
      const reps = v.reps_done ?? this.setValue(ex.id, setNum, 'reps_done', ex);
      const load = v.load_used ?? this.setValue(ex.id, setNum, 'load_used', ex);
      const rpe = v.rpe ?? this.setValue(ex.id, setNum, 'rpe', ex);
      const notes = v.notes ?? '';

      const sub = this.substituted[ex.id];

      const payload = {
        workout_exercise_id: ex.added ? null : ex.id,
        exercise_id: ex.added ? ex.exercise_id : null,
        set_number: setNum,
        reps_done: reps !== '' && reps !== null ? parseInt(reps) : null,
        load_used: load !== '' && load !== null ? parseFloat(load) : null,
        load_unit: ex.load_unit || 'KG',
        rpe: rpe ? parseInt(rpe) : null,
        notes: notes || '',
        completed,
        is_extra_set: ex.added || setNum > ex.sets,
        exercise_substituted: !ex.added && !!sub,
        actual_exercise_id: ex.added ? ex.exercise_id : (sub ? sub.id : null),
      };

      // Mark done locally — reassign array to trigger Alpine reactivity
      if (completed) {
        const arr = this.doneSets[ex.id] || [];
        if (!arr.includes(setNum)) {
          this.doneSets[ex.id] = [...arr, setNum].sort((a, b) => a - b);
        }
      }
      this.localValues[k] = { ...v, reps_done: payload.reps_done, load_used: payload.load_used, rpe: payload.rpe };

      try {
        const r = await fetch(this.urls.log_set_tpl.replace('__SID__', this.sessionId), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this._csrf() },
          body: JSON.stringify(payload),
        });
        if (!r.ok) throw new Error('log failed');
      } catch (e) {
        this._queuePending(payload);
      }
      try { navigator.vibrate && navigator.vibrate(60); } catch (_) {}
    },

    // ---- End exercise: collapse + open next ----
    endExercise(ex) {
      this.expanded[ex.id] = false;
      // Find next non-complete exercise
      const idx = this.exercises.findIndex(x => x.id === ex.id);
      for (let i = idx + 1; i < this.exercises.length; i++) {
        if (!this.isExComplete(this.exercises[i]) && !this.removed[this.exercises[i].id]) {
          this.expanded[this.exercises[i].id] = true;
          this.activeExId = this.exercises[i].id;
          // Scroll into view
          setTimeout(() => {
            const el = document.querySelectorAll('.ss-ex')[i];
            if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
          }, 200);
          return;
        }
      }
    },

    // ---- Substitute ----
    askSubstitute(ex) {
      this.substituteModal = { open: true, ex };
    },

    confirmSubstitute() {
      const ex = this.substituteModal.ex;
      if (ex && ex.alternative_exercise) {
        this.substituted = { ...this.substituted, [ex.id]: ex.alternative_exercise };
      }
      this.substituteModal.open = false;
      this.saveOverrides();
    },

    undoSubstitute(ex) {
      const next = { ...this.substituted };
      delete next[ex.id];
      this.substituted = next;
      this.saveOverrides();
    },

    // ---- Timer (per exercise) ----
    _startTimer(exId, sec) {
      const t = this.timers[exId];
      if (t && t._h) clearInterval(t._h);
      this.timers[exId] = { active: true, paused: false, sec, _h: null };
      this.timers[exId]._h = setInterval(() => {
        if (!this.timers[exId] || this.timers[exId].paused) return;
        this.timers[exId].sec -= 1;
        if (this.timers[exId].sec <= 0) {
          clearInterval(this.timers[exId]._h);
          this.timers[exId].active = false;
          try { navigator.vibrate && navigator.vibrate([200, 100, 200, 100, 200]); } catch (_) {}
          this._beep();
        }
      }, 1000);
    },

    toggleTimer(exId) {
      const t = this.timers[exId];
      if (!t) return;
      t.paused = !t.paused;
    },

    adjustTimer(exId, delta) {
      const t = this.timers[exId];
      if (!t) return;
      t.sec = Math.max(0, t.sec + delta);
    },

    _beep() {
      try {
        const ctx = new (window.AudioContext || window.webkitAudioContext)();
        const o = ctx.createOscillator();
        const g = ctx.createGain();
        o.connect(g); g.connect(ctx.destination);
        o.frequency.value = 880;
        g.gain.setValueAtTime(0.0001, ctx.currentTime);
        g.gain.exponentialRampToValueAtTime(0.4, ctx.currentTime + 0.01);
        g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.5);
        o.start();
        o.stop(ctx.currentTime + 0.5);
      } catch (_) {}
    },

    // ---- Pending queue ----
    _queuePending(payload) {
      try {
        const key = 'session_pending_' + this.sessionId;
        const cur = JSON.parse(localStorage.getItem(key) || '[]');
        cur.push(payload);
        localStorage.setItem(key, JSON.stringify(cur));
      } catch (_) {}
    },

    async _flushPending() {
      if (!this.sessionId) return;
      const key = 'session_pending_' + this.sessionId;
      try {
        const arr = JSON.parse(localStorage.getItem(key) || '[]');
        if (!arr.length) return;
        for (const p of arr) {
          await fetch(this.urls.log_set_tpl.replace('__SID__', this.sessionId), {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this._csrf() },
            body: JSON.stringify(p),
          });
        }
        localStorage.removeItem(key);
      } catch (_) {}
    },

    _collectExerciseNotes() {
      // Added exercises ('add-<id>') have no plan slot to attach notes to
      return Object.entries(this.exerciseNotes || {})
        .filter(([id, v]) => !String(id).startsWith('add-') && v && String(v).trim())
        .map(([id, v]) => ({ workout_exercise_id: Number(id), notes: String(v).trim() }));
    },

    // ---- Finalize ----
    async interrupt() {
      try {
        await fetch(this.urls.finish_tpl.replace('__SID__', this.sessionId), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this._csrf() },
          body: JSON.stringify({
            notes: this.finalNotes || '(interrotta)',
            interrupted: true,
            exercise_notes: this._collectExerciseNotes(),
          }),
        });
      } catch (_) {}
      window.location.href = this.urls.back;
    },

    async uploadMedia(event) {
      const files = Array.from(event.target.files || []);
      for (const f of files) {
        this.uploadingCount += 1;
        const fd = new FormData();
        fd.append('file', f);
        try {
          const r = await fetch(this.urls.media_tpl.replace('__SID__', this.sessionId), {
            method: 'POST',
            headers: { 'X-CSRFToken': this._csrf() },
            body: fd,
          });
          if (r.ok) {
            const d = await r.json();
            this.uploaded.push({ id: d.media_id, url: d.url, type: d.type });
          }
        } catch (_) {}
        this.uploadingCount -= 1;
      }
    },

    async finalize() {
      if (this.uploadingCount > 0) {
        Alpine.store('toasts').push({ kind: 'warn', msg: 'Attendi il completamento del caricamento media…' });
        return;
      }
      this.finalizing = true;
      try {
        await fetch(this.urls.finish_tpl.replace('__SID__', this.sessionId), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this._csrf() },
          body: JSON.stringify({
            notes: this.finalNotes,
            interrupted: false,
            exercise_notes: this._collectExerciseNotes(),
          }),
        });
        window.location.href = this.urls.back;
      } catch (e) {
        this.finalizing = false;
        toastError('Errore salvataggio.');
      }
    },

  };
}
window.sessionRunner = sessionRunner;
