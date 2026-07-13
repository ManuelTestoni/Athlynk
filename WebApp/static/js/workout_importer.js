// Importer scheda di allenamento — Alpine factory.
// Costruito sopra createImportWizardCore (step machine, polling, dropzone).
// Aggiunge: hydrateWorkout, exercise search & match resolve, volume analytics,
// drawer "crea esercizio personalizzato", save (confirm endpoint).

(function () {
  'use strict';

  const DAY_LABELS_IT = {
    MONDAY: 'Lunedì', TUESDAY: 'Martedì', WEDNESDAY: 'Mercoledì',
    THURSDAY: 'Giovedì', FRIDAY: 'Venerdì', SATURDAY: 'Sabato', SUNDAY: 'Domenica',
  };

  const BLOCK_TYPE_LABELS = {
    straight: 'Singolo', superset: 'Superset', circuit: 'Circuit',
    emom: 'EMOM', amrap: 'AMRAP',
  };

  const BLOCK_TYPE_COLORS = {
    // superset used to be "aegean" and circuit "bronze" — both now resolve to
    // the same primary blue post-rebrand, so superset gets a literal teal to
    // stay visually distinct from circuit.
    straight: 'var(--al-ink-mute)', superset: '#2B6E6E',
    circuit: 'var(--al-bronze)', emom: 'var(--al-warn)', amrap: 'var(--al-danger)',
  };

  function createWorkoutImporter(userConfig) {
    const core = window.createImportWizardCore(userConfig);

    const extension = {
      workout: { sessions: [], plan_name: null, goal: null,
                 frequency_per_week: null, notes: null,
                 extraction_notes: [], document_summary: null },
      confidence: { fields_total: 0, fields_uncertain: 0, ratio: 0 },
      documentSummary: null,
      activeSession: 0,

      // Plan kind selection (step 1)
      planKind: 'WEEKLY',     // 'WEEKLY' | 'PROGRAM'
      durationWeeks: 1,

      // Volume analytics toggle
      histoShow: { sets: true, reps: true, load: false },

      // Custom exercise drawer
      customExerciseOpen: false,
      customExercise: null,
      muscleGroups: [],
      equipmentOptions: [],
      categoryOptions: [],

      init() {
        this._initCore();
        this._loadTaxonomy();
        this.customExercise = this._emptyCustomExercise();
      },

      // ─── Override apply ─────────────────────────────────────
      applyExtractionResult(data) {
        const extracted = data.extracted || {};
        this.workout = this.hydrateWorkout(extracted);
        this.confidence = data.confidence || { fields_total: 0, fields_uncertain: 0, ratio: 0 };
        this.documentSummary = data.document_summary
            || extracted.document_summary
            || null;
        if (data.client) this.selectedClient = data.client;
        if (data.plan_title) this.planTitle = data.plan_title;
        this.activeSession = 0;
        this.currentStep = 3;
      },

      hydrateWorkout(raw) {
        const hydrateEx = (e) => ({
          raw_name: e.raw_name || '',
          matched_exercise_id: e.matched_exercise_id || null,
          matched_exercise_name: e.matched_exercise_name || null,
          matched_primary_muscle: e.matched_primary_muscle || '',
          matched_equipment: e.matched_equipment || '',
          match_confidence: e.match_confidence || 'none',
          match_method: e.match_method || null,
          uncertain: !!e.uncertain || !e.matched_exercise_id,
          sets: e.sets ?? null,
          reps: e.reps ?? null,
          reps_type: e.reps_type || (typeof e.reps === 'string' && e.reps.includes('-') ? 'range' : 'fixed'),
          load: e.load ?? null,
          load_unit: e.load_unit || null,
          load_type: e.load_type || 'absolute',
          rpe: e.rpe ?? null,
          rir: e.rir ?? null,
          tempo: e.tempo || null,
          rest_seconds: e.rest_seconds ?? null,
          rest_label: e.rest_label || null,
          distance: e.distance ?? null,
          distance_unit: e.distance_unit || null,
          duration_seconds: e.duration_seconds ?? null,
          notes: e.notes || null,
          source_page: e.source_page ?? null,
          source_chunk: e.source_chunk ?? null,
          _candidates: e.candidates || [],
          _searchOpen: false,
          _dropdownStyle: '',
        });
        const sessions = (raw.sessions || []).map((s, idx) => ({
          day_label: s.day_label || ('Giorno ' + (idx + 1)),
          day_of_week: s.day_of_week || null,
          session_type: s.session_type || null,
          order_index: s.order_index ?? idx,
          notes: s.notes || null,
          blocks: (s.blocks || []).map(b => ({
            block_name: b.block_name || null,
            block_type: b.block_type || 'straight',
            exercises: (b.exercises || []).map(hydrateEx),
          })),
        }));
        return {
          plan_name: raw.plan_name || null,
          goal: raw.goal || null,
          frequency_per_week: raw.frequency_per_week || null,
          notes: raw.notes || null,
          extraction_notes: raw.extraction_notes || [],
          document_summary: raw.document_summary || null,
          sessions,
        };
      },

      // ─── Labels / formatting helpers ──────────────────────
      dayLabel(s) {
        if (s.day_label) return s.day_label;
        return DAY_LABELS_IT[s.day_of_week] || ('Giorno ' + ((s.order_index ?? 0) + 1));
      },
      blockTypeLabel(t) { return BLOCK_TYPE_LABELS[t] || 'Singolo'; },
      blockTypeColor(t) { return BLOCK_TYPE_COLORS[t] || 'var(--al-ink-mute)'; },

      formatReps(ex) {
        if (ex.reps == null) return '—';
        return String(ex.reps);
      },

      formatLoad(ex) {
        if (ex.load == null) return '—';
        if (ex.load_type === 'percentage_1rm') return ex.load + '% 1RM';
        const unit = ex.load_unit === 'bw' ? 'bw' : (ex.load_unit || 'kg');
        return ex.load + ' ' + unit;
      },

      formatRest(ex) {
        if (ex.rest_seconds) {
          const s = ex.rest_seconds;
          if (s >= 60) return Math.floor(s / 60) + "'" + (s % 60 ? (s % 60) + '"' : '');
          return s + 's';
        }
        return ex.rest_label || '—';
      },

      // ─── Exercise search & resolve ────────────────────────
      async searchExerciseInline(ex, query) {
        if (!query || query.length < 2) return;
        try {
          const r = await fetch('/api/exercises/search/?q=' + encodeURIComponent(query));
          if (r.ok) ex._candidates = await r.json();
        } catch (e) { console.error(e); }
      },

      // Anchor the teleported dropdown to the search input's bbox so it remains
      // visible even when the row sits at the bottom of an overflow:hidden card.
      openExerciseSearch(ex, anchorEl) {
        ex._searchOpen = true;
        if (!anchorEl) return;
        this._positionDropdown(ex, anchorEl);
        // Reposition on scroll/resize while this dropdown is open.
        const reflow = () => {
          if (!ex._searchOpen) {
            window.removeEventListener('scroll', reflow, true);
            window.removeEventListener('resize', reflow);
            return;
          }
          this._positionDropdown(ex, anchorEl);
        };
        window.addEventListener('scroll', reflow, true);
        window.addEventListener('resize', reflow);
      },

      _positionDropdown(ex, anchorEl) {
        const r = anchorEl.getBoundingClientRect();
        const maxH = 280;
        const spaceBelow = window.innerHeight - r.bottom;
        const placeAbove = spaceBelow < 200 && r.top > 220;
        const left = Math.min(r.left, window.innerWidth - Math.max(r.width, 320) - 12);
        const top = placeAbove ? Math.max(8, r.top - 6 - maxH) : (r.bottom + 6);
        ex._dropdownStyle =
          `position: fixed;`
          + ` top: ${Math.round(top)}px;`
          + ` left: ${Math.round(left)}px;`
          + ` width: ${Math.max(Math.round(r.width), 320)}px;`
          + ` max-height: ${maxH}px;`
          + ` z-index: 9999;`;
      },

      pickExercise(ex, candidate) {
        ex.matched_exercise_id = candidate.id;
        ex.matched_exercise_name = candidate.name;
        ex.matched_primary_muscle = candidate.primary_muscle
            || (candidate.primary_muscles && candidate.primary_muscles[0]?.name)
            || '';
        ex.matched_equipment = Array.isArray(candidate.equipment)
            ? candidate.equipment.join(', ')
            : (candidate.equipment || '');
        ex.raw_name = candidate.name;
        ex.match_confidence = 'manual';
        ex.match_method = 'manual';
        ex.uncertain = false;
        ex._candidates = [];
        ex._searchOpen = false;
      },

      addExercise(sIdx, bIdx) {
        const block = this.workout.sessions[sIdx].blocks[bIdx];
        block.exercises.push({
          raw_name: '', matched_exercise_id: null, matched_exercise_name: null,
          match_confidence: 'none', match_method: null, uncertain: true,
          sets: 3, reps: '8-10', reps_type: 'range',
          load: null, load_unit: null, load_type: 'absolute',
          rpe: null, rir: null, tempo: null,
          rest_seconds: 90, rest_label: null,
          distance: null, distance_unit: null, duration_seconds: null,
          notes: null, source_page: null, source_chunk: null,
          _candidates: [], _searchOpen: true, _dropdownStyle: '',
        });
      },

      removeExercise(sIdx, bIdx, eIdx) {
        this.workout.sessions[sIdx].blocks[bIdx].exercises.splice(eIdx, 1);
      },

      addBlock(sIdx, blockType) {
        this.workout.sessions[sIdx].blocks.push({
          block_name: null, block_type: blockType || 'straight', exercises: [],
        });
      },

      removeBlock(sIdx, bIdx) {
        this.workout.sessions[sIdx].blocks.splice(bIdx, 1);
      },

      addSession() {
        const idx = this.workout.sessions.length;
        this.workout.sessions.push({
          day_label: 'Giorno ' + (idx + 1),
          day_of_week: null, session_type: null, order_index: idx, notes: null,
          blocks: [{ block_name: null, block_type: 'straight', exercises: [] }],
        });
        this.activeSession = idx;
      },

      removeSession(idx) {
        this.workout.sessions.splice(idx, 1);
        if (this.activeSession >= this.workout.sessions.length) {
          this.activeSession = Math.max(0, this.workout.sessions.length - 1);
        }
      },

      // ─── Volume analytics ────────────────────────────────
      sessionVolume(s) {
        let totalSets = 0, totalReps = 0, totalLoad = 0;
        for (const b of s.blocks || []) {
          for (const e of b.exercises || []) {
            const sets = parseInt(e.sets) || 0;
            const reps = parseInt(e.reps) || 0;
            const load = parseFloat(e.load) || 0;
            totalSets += sets;
            totalReps += sets * reps;
            if (e.load_type === 'absolute' && e.load_unit !== 'bw') totalLoad += sets * reps * load;
          }
        }
        return { sets: totalSets, reps: totalReps, load: Math.round(totalLoad) };
      },

      totalSets() {
        let n = 0;
        for (const s of this.workout.sessions || []) n += this.sessionVolume(s).sets;
        return n;
      },

      totalExercises() {
        let n = 0;
        for (const s of this.workout.sessions || []) {
          for (const b of s.blocks || []) n += (b.exercises || []).length;
        }
        return n;
      },

      uncertainCount() {
        let n = 0;
        for (const s of this.workout.sessions || []) {
          for (const b of s.blocks || []) {
            for (const e of b.exercises || []) {
              if (e.uncertain || !e.matched_exercise_id) n++;
            }
          }
        }
        return n;
      },

      // ─── Volume analytics (mirrors builder behaviour) ─────
      _exerciseSetCount(e) { return parseInt(e.sets) || 0; },
      _exerciseRepCount(e) {
        if (e.reps == null) return 0;
        if (typeof e.reps === 'number') return e.reps;
        const m = String(e.reps).match(/(\d+)(?:\s*[-–]\s*(\d+))?/);
        if (!m) return 0;
        return m[2] ? Math.round((parseInt(m[1]) + parseInt(m[2])) / 2) : parseInt(m[1]) || 0;
      },

      muscleSegments() {
        // Sets per primary muscle. Same formula as builder (primary ×1).
        const buckets = {};
        for (const s of this.workout.sessions || []) {
          for (const b of s.blocks || []) {
            for (const e of b.exercises || []) {
              const sets = this._exerciseSetCount(e);
              if (!sets) continue;
              const key = (e.matched_primary_muscle || '').trim() || 'Non specificato';
              buckets[key] = (buckets[key] || 0) + sets;
            }
          }
        }
        const total = Object.values(buckets).reduce((a, b) => a + b, 0) || 1;
        // "aegean" now resolves to the same primary blue as "bronze" post-rebrand,
        // so slots that used to be var-based and distinct are now literal jewel
        // tones instead, keeping all 9 donut segments mutually distinguishable.
        const palette = ['var(--al-bronze)', '#2B6E6E', 'var(--al-warn)',
                          'var(--al-danger)', 'var(--al-ink-mute)', '#8A6E5A',
                          '#4F7A6A', '#8A5A6B', '#3F7690'];
        const entries = Object.entries(buckets).sort((a, b) => b[1] - a[1]);
        let acc = 0;
        return entries.map(([label, count], i) => {
          const pct = count / total;
          const seg = { key: label, label, count, pct,
                         start: acc, end: acc + pct, color: palette[i % palette.length] };
          acc += pct;
          return seg;
        });
      },

      // Per-session histogram data (matches diet wizard's weekChartData shape).
      sessionHistogramData() {
        return (this.workout.sessions || []).map((s, idx) => {
          const v = this.sessionVolume(s);
          return {
            code: idx,
            label: this.dayLabel(s),
            sets: v.sets,
            reps: v.reps,
            load: v.load,
          };
        });
      },

      sessionHistogramMax() {
        const data = this.sessionHistogramData();
        let m = 0;
        for (const d of data) {
          if (d.sets > m) m = d.sets;
          if (d.reps > m) m = d.reps;
        }
        return m || 1;
      },

      histoBarHeight(value, max, fullHeight) {
        if (!max) return 0;
        return Math.max(2, Math.round((value / max) * fullHeight));
      },

      toggleHisto(key) { this.histoShow[key] = !this.histoShow[key]; },

      donutPath(start, end, cx, cy, rOuter, rInner) {
        const a0 = (start - 0.25) * Math.PI * 2;
        const a1 = (end - 0.25) * Math.PI * 2;
        const large = end - start > 0.5 ? 1 : 0;
        const x0 = cx + rOuter * Math.cos(a0), y0 = cy + rOuter * Math.sin(a0);
        const x1 = cx + rOuter * Math.cos(a1), y1 = cy + rOuter * Math.sin(a1);
        const x2 = cx + rInner * Math.cos(a1), y2 = cy + rInner * Math.sin(a1);
        const x3 = cx + rInner * Math.cos(a0), y3 = cy + rInner * Math.sin(a0);
        return `M ${x0} ${y0} A ${rOuter} ${rOuter} 0 ${large} 1 ${x1} ${y1} L ${x2} ${y2} A ${rInner} ${rInner} 0 ${large} 0 ${x3} ${y3} Z`;
      },

      // ─── Custom exercise drawer ─────────────────────────
      _emptyCustomExercise() {
        return {
          name: '', category_id: null, primary_muscle_ids: [], secondary_muscle_ids: [],
          equipment_ids: [], coach_notes: '',
          saving: false, error: '',
        };
      },

      async _loadTaxonomy() {
        try {
          const [mr, fr] = await Promise.all([
            fetch('/api/muscle-groups/'),
            fetch('/api/exercises/filters/'),
          ]);
          if (mr.ok) this.muscleGroups = await mr.json();
          if (fr.ok) {
            const f = await fr.json();
            this.equipmentOptions = f.equipment || [];
            this.categoryOptions = f.categories || [];
          }
        } catch (e) { console.warn('taxonomy fetch fail', e); }
      },

      openCustomExerciseDrawer(forEx) {
        this.customExercise = this._emptyCustomExercise();
        // Prefill name from current row search query if present
        if (forEx && forEx.raw_name) this.customExercise.name = forEx.raw_name;
        this._customTargetEx = forEx || null;
        this.customExerciseOpen = true;
      },

      closeCustomExerciseDrawer() {
        this.customExerciseOpen = false;
        this._customTargetEx = null;
      },

      toggleCustomMulti(field, id) {
        const arr = this.customExercise[field];
        const i = arr.indexOf(id);
        if (i >= 0) arr.splice(i, 1); else arr.push(id);
      },

      async saveCustomExercise() {
        const ce = this.customExercise;
        ce.error = '';
        if ((ce.name || '').trim().length < 3) { ce.error = 'Nome: minimo 3 caratteri.'; return; }
        if (!ce.primary_muscle_ids.length) { ce.error = 'Seleziona almeno un muscolo primario.'; return; }
        ce.saving = true;
        try {
          const r = await fetch('/api/exercises/custom/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this.csrf },
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
          this.flashToast('Esercizio personalizzato creato.');
          // If we opened the drawer from an exercise row, link it directly.
          if (this._customTargetEx) {
            this.pickExercise(this._customTargetEx, {
              id: d.id, name: d.name,
              primary_muscle: (d.primary_muscles || [])[0]?.name || '',
            });
          }
          this.closeCustomExerciseDrawer();
        } catch (e) { ce.error = 'Errore di rete.'; }
        ce.saving = false;
      },

      // ─── Save (confirm) ─────────────────────────────────
      async reset() {
        if (!await window.alConfirm({ variant: 'neutral', icon: 'ph-arrow-counter-clockwise', title: 'Ricominciare\nda capo?', subtitle: 'Tutte le modifiche andranno perse.', confirmLabel: 'Sì, ricomincia' })) return;
        this.stopPolling(); this.stopLoadingAnim();
        this.currentStep = 1;
        this.file = null;
        this.jobId = null;
        this.pendingResult = null;
        this.targetPhase = 0;
        this.displayedPhase = 0;
        this.workout = { sessions: [], plan_name: null, goal: null,
                         frequency_per_week: null, notes: null, extraction_notes: [], document_summary: null };
        this.confidence = { fields_total: 0, fields_uncertain: 0, ratio: 0 };
      },

      async save() {
        if (this.uncertainCount() > 0) {
          await window.alAlert({ variant: 'neutral', icon: 'ph-warning', title: 'Esercizi non\nrisolti', subtitle: 'Ci sono ' + this.uncertainCount() + ' esercizi non risolti. Risolvili prima di salvare.' });
          return;
        }
        this.saving = true;
        const payload = {
          plan_title: this.planTitle,
          client_id: this.selectedClient?.id || null,
          assign_now: false,
          plan_kind: this.planKind,
          duration_weeks: this.planKind === 'PROGRAM' ? this.durationWeeks : 1,
          workout_json: {
            plan_name: this.planTitle,
            goal: this.workout.goal,
            frequency_per_week: this.workout.frequency_per_week,
            notes: this.workout.notes,
            sessions: this.workout.sessions.map((s, idx) => ({
              day_label: s.day_label,
              day_of_week: s.day_of_week,
              session_type: s.session_type,
              order_index: idx,
              notes: s.notes,
              blocks: s.blocks.map(b => ({
                block_name: b.block_name,
                block_type: b.block_type || 'straight',
                exercises: b.exercises.map(e => ({
                  raw_name: e.raw_name,
                  matched_exercise_id: e.matched_exercise_id,
                  matched_exercise_name: e.matched_exercise_name,
                  match_confidence: e.match_confidence,
                  match_method: e.match_method,
                  uncertain: !!e.uncertain,
                  sets: e.sets, reps: e.reps, reps_type: e.reps_type,
                  load: e.load, load_unit: e.load_unit, load_type: e.load_type,
                  rpe: e.rpe, rir: e.rir, tempo: e.tempo,
                  rest_seconds: e.rest_seconds, rest_label: e.rest_label,
                  distance: e.distance, distance_unit: e.distance_unit,
                  duration_seconds: e.duration_seconds,
                  notes: e.notes,
                })),
              })),
            })),
          },
        };
        try {
          const r = await fetch('/api/allenamenti/import/conferma/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this.csrf },
            body: JSON.stringify(payload),
          });
          const data = await r.json().catch(() => ({}));
          this.saving = false;
          if (!r.ok) {
            this.errorMsg = this.translateError({ error: data.error, detail: data.detail });
            this.currentStep = 'error';
            return;
          }
          this.flashToast('Scheda salvata con successo!');
          setTimeout(() => { window.location.href = data.redirect_url || '/allenamenti/'; }, 1200);
        } catch (e) {
          this.saving = false;
          this.errorMsg = 'Errore di rete: ' + (e.message || e);
          this.currentStep = 'error';
        }
      },
    };

    return Object.assign(core, extension);
  }

  window.createWorkoutImporter = createWorkoutImporter;
})();
