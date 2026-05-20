/**
 * Athlynk · Volume Analytics Drawer
 *
 * Self-contained Alpine component rendering a slide-over drawer with three
 * Chart.js views (histogram, line, radar) over a workout plan's per-week,
 * per-muscle-group volume.
 *
 * Open with: `AthlynkVolume.open(payload)` where payload =
 *   {
 *     planKind:   'WEEKLY' | 'PROGRAM',
 *     durationWeeks: int,
 *     days:       [{ exercises: [{
 *                       sets, reps, primary_muscles: [{slug,name,color_token}],
 *                       secondary_muscles: [...],
 *                       primary_muscle_text: 'Petto',  // fallback
 *                       weekly_overrides: { 1: {sets, reps}, ... } (optional)
 *                    }] }]
 *   }
 *
 * Computation is fully client-side so the drawer works on unsaved drafts too.
 */
(function () {
  const MG_PALETTE = {
    'mg-chest':     '#8a3a3a',
    'mg-back':      '#1c4a52',
    'mg-shoulders': '#a78554',
    'mg-quads':     '#2a6a72',
    'mg-hams':      '#5a8a3a',
    'mg-glutes':    '#8a6a3a',
    'mg-calves':    '#c8a774',
    'mg-biceps':    '#4a6b3a',
    'mg-triceps':   '#a6802b',
    'mg-abs':       '#5b554a',
    'mg-forearms':  '#8a8270',
    'mg-other':     '#c4b89c',
  };

  const WEEK_COLORS = ['#1c4a52', '#8a6a3a', '#a6802b', '#4a6b3a', '#8a3a3a', '#2a6a72'];

  function _hexWithAlpha(hex, alpha) {
    if (typeof hex !== 'string') return hex;
    let h = hex.replace('#', '');
    if (h.length === 3) h = h.split('').map(c => c + c).join('');
    const r = parseInt(h.slice(0, 2), 16);
    const g = parseInt(h.slice(2, 4), 16);
    const b = parseInt(h.slice(4, 6), 16);
    const a = Math.max(0, Math.min(1, alpha));
    return `rgba(${r}, ${g}, ${b}, ${a})`;
  }

  function parseRepCount(raw) {
    if (raw === null || raw === undefined) return 0;
    if (typeof raw === 'number') return raw;
    const matches = String(raw).match(/\d+/g);
    if (!matches) return 0;
    return Math.max(...matches.map(Number));
  }

  document.addEventListener('alpine:init', () => {
    Alpine.data('volumeAnalytics', () => ({
      /* lifecycle */
      isOpen: false,
      payload: null,           // captured plan snapshot
      durationWeeks: 1,
      planKind: 'WEEKLY',

      /* UI state */
      chartType: 'histogram',
      weeksSelected: [],
      groupsSelected: [],
      showSecondary: true,

      /* computed cache */
      computedGroups: [],      // [{slug, name, color_token, per_week: [{week, primary_sets, secondary_sets}]}]
      _chart: null,
      _canvas: null,

      /* === Public lifecycle === */
      init() {
        // Stash the reactive proxy globally so external code can call us directly,
        // regardless of event-listener timing quirks.
        window.__athlynkVolumeDrawer = this;

        window.addEventListener('volume-analytics:open', (e) => this.handleOpen(e.detail));
        window.addEventListener('volume-analytics:refresh', (e) => this.handleRefresh(e.detail));
        window.addEventListener('keydown', (e) => {
          if (e.key === 'Escape' && this.isOpen) this.close();
        });
      },

      handleOpen(detail) {
        const p = detail || {};
        this.planKind = (p.planKind || 'WEEKLY').toUpperCase();
        this.durationWeeks = Math.max(1, parseInt(p.durationWeeks || 1, 10));
        this.payload = p.days || [];
        this.isOpen = true;
        document.body.style.overflow = 'hidden';
        this.chartType = this.planKind === 'PROGRAM' ? 'line' : 'histogram';

        if (p.planId && !(p.days && p.days.length)) {
          // Plan-detail path: pull pre-computed volume from server.
          this._loadFromServer(p.planId);
        } else {
          this.compute();
          this.weeksSelected = this._allWeeks();
          this.groupsSelected = this.computedGroups.map(g => g.slug);
          // Render after drawer slide finishes so canvas has measurable size.
          setTimeout(() => { if (this.isOpen && this.hasData()) this.renderChart(); }, 360);
        }
      },

      _loadFromServer(planId) {
        this.computedGroups = [];
        this.weeksSelected = [];
        this.groupsSelected = [];
        fetch(`/api/allenamenti/${planId}/volume/`, { credentials: 'same-origin' })
          .then(r => r.ok ? r.json() : Promise.reject(r.status))
          .then(d => {
            this.durationWeeks = Math.max(1, parseInt(d.duration_weeks || 1, 10));
            this.planKind = (d.plan_kind || this.planKind || 'WEEKLY').toUpperCase();
            this.computedGroups = (d.muscle_groups || []).map(g => ({
              slug: g.slug,
              name: g.name,
              color_token: g.color_token,
              per_week: g.per_week || [],
            }));
            this.weeksSelected = d.weeks && d.weeks.length ? d.weeks.slice() : this._allWeeks();
            this.groupsSelected = this.computedGroups.map(g => g.slug);
            if (!this.chartType || this.chartType === 'histogram') {
              this.chartType = this.planKind === 'PROGRAM' ? 'line' : 'histogram';
            }
            // Render after drawer slide finishes so canvas has measurable width.
            setTimeout(() => { if (this.isOpen && this.hasData()) this.renderChart(); }, 400);
          })
          .catch(err => console.error('[AthlynkVolume] server load failed', err));
      },

      close() {
        this.isOpen = false;
        document.body.style.overflow = '';
        this._destroyChart();
        window.dispatchEvent(new CustomEvent('volume-analytics:closed'));
      },

      handleRefresh(detail) {
        if (!this.isOpen) return;
        const p = detail || {};
        if (p.durationWeeks != null) {
          this.durationWeeks = Math.max(1, parseInt(p.durationWeeks, 10));
        }
        if (p.days != null) this.payload = p.days;
        if (p.planKind) this.planKind = String(p.planKind).toUpperCase();

        const prevGroups = new Set(this.groupsSelected);
        const prevWeeks = new Set(this.weeksSelected);
        this.compute();

        const newWeeks = this._allWeeks();
        const keptWeeks = newWeeks.filter(w => prevWeeks.has(w));
        this.weeksSelected = keptWeeks.length ? keptWeeks : newWeeks;

        const allSlugs = this.computedGroups.map(g => g.slug);
        const keptGroups = allSlugs.filter(s => prevGroups.has(s));
        this.groupsSelected = keptGroups.length ? keptGroups : allSlugs;

        this.$nextTick(() => this.renderChart());
      },

      /* === Compute volume from plan data === */
      compute() {
        const map = new Map();   // slug -> {slug, name, color_token, per_week: { week: {p, s} } }
        const weeks = this._allWeeks();
        const days = this.payload || [];

        days.forEach(day => {
          (day.exercises || []).forEach(ex => {
            const baseSets = parseInt(ex.sets, 10) || 0;
            if (baseSets <= 0) return;

            const wkOverrides = ex.weekly_overrides || {};
            const primaries = ex.primary_muscles || [];
            const secondaries = ex.secondary_muscles || [];

            // Fallback to legacy text fields if no M2M data
            if (primaries.length === 0 && ex.primary_muscle_text) {
              primaries.push({
                slug: 'unknown-' + ex.primary_muscle_text.toLowerCase().replace(/\s+/g, '-'),
                name: ex.primary_muscle_text,
                color_token: 'mg-other',
              });
            }

            weeks.forEach(w => {
              const ov = wkOverrides[w] || null;
              const sets = ov && ov.sets != null ? parseInt(ov.sets, 10) : baseSets;
              if (!sets || sets <= 0) return;
              const vol = sets;

              primaries.forEach(m => {
                if (!map.has(m.slug)) {
                  map.set(m.slug, { slug: m.slug, name: m.name, color_token: m.color_token || 'mg-other', per_week: {} });
                }
                const bucket = map.get(m.slug).per_week;
                if (!bucket[w]) bucket[w] = { primary: 0, secondary: 0 };
                bucket[w].primary += vol;
              });
              secondaries.forEach(m => {
                if (!map.has(m.slug)) {
                  map.set(m.slug, { slug: m.slug, name: m.name, color_token: m.color_token || 'mg-other', per_week: {} });
                }
                const bucket = map.get(m.slug).per_week;
                if (!bucket[w]) bucket[w] = { primary: 0, secondary: 0 };
                bucket[w].secondary += vol * 0.5;
              });
            });
          });
        });

        // Flatten
        this.computedGroups = Array.from(map.values()).map(g => ({
          slug: g.slug,
          name: g.name,
          color_token: g.color_token,
          per_week: weeks.map(w => ({
            week: w,
            primary_sets: g.per_week[w]?.primary || 0,
            secondary_sets: g.per_week[w]?.secondary || 0,
          })),
        }));

        // Sort by total volume desc
        this.computedGroups.sort((a, b) => {
          const sumA = a.per_week.reduce((t, x) => t + x.primary_sets + x.secondary_sets, 0);
          const sumB = b.per_week.reduce((t, x) => t + x.primary_sets + x.secondary_sets, 0);
          return sumB - sumA;
        });
      },

      _allWeeks() {
        return Array.from({ length: this.durationWeeks }, (_, i) => i + 1);
      },

      hasData() {
        return this.computedGroups.length > 0;
      },

      /* === Selection / interaction === */
      toggleWeek(w) {
        const i = this.weeksSelected.indexOf(w);
        if (i >= 0) this.weeksSelected.splice(i, 1);
        else this.weeksSelected.push(w);
        this.weeksSelected.sort((a, b) => a - b);
        this.renderChart();
      },
      toggleGroup(slug) {
        const i = this.groupsSelected.indexOf(slug);
        if (i >= 0) this.groupsSelected.splice(i, 1);
        else this.groupsSelected.push(slug);
        this.renderChart();
      },
      selectAllGroups() {
        this.groupsSelected = this.computedGroups.map(g => g.slug);
        this.renderChart();
      },
      selectAllWeeks() {
        this.weeksSelected = this._allWeeks();
        this.renderChart();
      },
      setChartType(t) {
        if (this.chartType === t) return;
        this.chartType = t;
        this.renderChart();
      },
      setShowSecondary(v) {
        this.showSecondary = v;
        this.renderChart();
      },

      /* === Helpers === */
      activeGroups() {
        return this.computedGroups.filter(g => this.groupsSelected.includes(g.slug));
      },
      groupColor(g) { return MG_PALETTE[g.color_token] || '#8a6a3a'; },
      weekColor(idx) { return WEEK_COLORS[idx % WEEK_COLORS.length]; },
      groupTotalForWeek(g, w) {
        const cell = (g.per_week || []).find(c => c.week === w);
        if (!cell) return 0;
        return (cell.primary_sets || 0) + (this.showSecondary ? (cell.secondary_sets || 0) : 0);
      },

      diffPayload() {
        if (this.weeksSelected.length < 2) return null;
        const ws = this.weeksSelected.slice().sort((a, b) => a - b);
        const wFirst = ws[0], wLast = ws[ws.length - 1];
        const rows = [];
        let totalDelta = 0;
        this.activeGroups().forEach(g => {
          const a = this.groupTotalForWeek(g, wFirst);
          const b = this.groupTotalForWeek(g, wLast);
          const delta = b - a;
          totalDelta += delta;
          rows.push({ name: g.name, delta });
        });
        rows.sort((x, y) => Math.abs(y.delta) - Math.abs(x.delta));
        return { wFirst, wLast, rows, totalDelta };
      },

      /* === Chart === */
      _destroyChart() {
        if (this._chart) { this._chart.destroy(); this._chart = null; }
      },

      mountCanvas(el) {
        this._canvas = el;
        // Single render path lives in handleOpen / _loadFromServer to avoid
        // a destroy+recreate flicker that briefly exposes the parchment bg.
      },

      _resizeChart() {
        if (this._chart && typeof this._chart.resize === 'function') {
          try { this._chart.resize(); } catch (_) { /* ignore */ }
        }
      },

      renderChart() {
        this._destroyChart();
        if (!this._canvas) {
          // Canvas not mounted yet — retry shortly.
          setTimeout(() => { if (this.isOpen && this.hasData()) this.renderChart(); }, 120);
          return;
        }
        if (typeof Chart === 'undefined') {
          console.warn('[AthlynkVolume] Chart.js not loaded');
          return;
        }
        const groups = this.activeGroups();
        if (!groups.length || !this.weeksSelected.length) return;

        // Reset any inline sizing — Chart.js handles canvas dimensions and
        // devicePixelRatio scaling when responsive: true. Manually setting
        // canvas.width = w*dpr collided with Chart's internal scaling and
        // pushed content outside the visible area.
        this._canvas.removeAttribute('width');
        this._canvas.removeAttribute('height');
        this._canvas.style.width = '';
        this._canvas.style.height = '';

        const ctx = this._canvas.getContext('2d');
        const baseOpts = {
          responsive: true,
          maintainAspectRatio: false,
          animation: { duration: 380, easing: 'easeOutCubic' },
          plugins: {
            legend: { display: false },
            tooltip: {
              backgroundColor: 'rgba(20,17,13,0.92)',
              titleColor: '#f4efe4',
              bodyColor: '#f4efe4',
              padding: 10,
              cornerRadius: 6,
              callbacks: {
                label: (c) => {
                  const v = c.parsed?.y ?? c.parsed?.r ?? c.parsed ?? 0;
                  return `${c.dataset.label}: ${(+v).toFixed(0)} serie`;
                },
              },
            },
          },
        };

        if (this.chartType === 'histogram') {
          this._renderHistogram(ctx, groups, baseOpts);
        } else if (this.chartType === 'line') {
          this._renderLine(ctx, groups, baseOpts);
        } else if (this.chartType === 'radar') {
          this._renderRadar(ctx, groups, baseOpts);
        }
      },

      _renderHistogram(ctx, groups, baseOpts) {
        // Color per muscle group. Multi-week: one dataset per week,
        // each dataset uses per-group colors with descending alpha across weeks.
        const labels = groups.map(g => g.name);
        const groupHex = groups.map(g => this.groupColor(g));
        const weeks = this.weeksSelected;
        const datasets = weeks.map((w, i) => {
          const alpha = Math.max(0.35, 1 - (i * (0.65 / Math.max(1, weeks.length - 1 || 1))));
          return {
            label: 'S' + w,
            data: groups.map(g => this.groupTotalForWeek(g, w)),
            backgroundColor: groupHex.map(h => _hexWithAlpha(h, alpha)),
            borderColor: groupHex,
            borderWidth: weeks.length > 1 ? 1 : 0,
            borderRadius: 6,
            borderSkipped: false,
            maxBarThickness: 32,
          };
        });
        this._chart = new Chart(ctx, {
          type: 'bar',
          data: { labels, datasets },
          options: {
            ...baseOpts,
            scales: {
              x: { grid: { display: false }, ticks: { color: '#5b554a', font: { size: 11 } } },
              y: { beginAtZero: true, grid: { color: 'rgba(91,85,74,0.12)' }, ticks: { color: '#5b554a', font: { size: 11 } } },
            },
          },
        });
      },

      _renderLine(ctx, groups, baseOpts) {
        // Color per muscle group. One line per group across selected weeks.
        const labels = this.weeksSelected.map(w => 'S' + w);
        const datasets = groups.map(g => {
          const c = this.groupColor(g);
          return {
            label: g.name,
            data: this.weeksSelected.map(w => this.groupTotalForWeek(g, w)),
            borderColor: c,
            backgroundColor: c,
            pointBackgroundColor: c,
            pointBorderColor: '#f4efe4',
            pointBorderWidth: 1.5,
            tension: 0.32,
            pointRadius: 5,
            pointHoverRadius: 7,
            borderWidth: 2.5,
            fill: false,
            spanGaps: true,
          };
        });
        this._chart = new Chart(ctx, {
          type: 'line',
          data: { labels, datasets },
          options: {
            ...baseOpts,
            scales: {
              x: { grid: { display: false }, ticks: { color: '#5b554a', font: { size: 11 } } },
              y: { beginAtZero: true, grid: { color: 'rgba(91,85,74,0.12)' }, ticks: { color: '#5b554a', font: { size: 11 } } },
            },
          },
        });
      },

      _renderRadar(ctx, groups, baseOpts) {
        // Color per week with transparency — weeks overlap as polygons.
        const labels = groups.map(g => g.name);
        const ws = this.weeksSelected.slice(0, 4);
        const datasets = ws.map((w, i) => {
          const color = this.weekColor(i);
          return {
            label: 'S' + w,
            data: groups.map(g => this.groupTotalForWeek(g, w)),
            borderColor: color,
            backgroundColor: _hexWithAlpha(color, 0.22),
            pointBackgroundColor: color,
            pointBorderColor: '#f4efe4',
            pointBorderWidth: 1.5,
            pointRadius: 4,
            pointHoverRadius: 6,
            borderWidth: 2,
          };
        });
        this._chart = new Chart(ctx, {
          type: 'radar',
          data: { labels, datasets },
          options: {
            ...baseOpts,
            scales: {
              r: {
                beginAtZero: true,
                angleLines: { color: 'rgba(91,85,74,0.15)' },
                grid: { color: 'rgba(91,85,74,0.10)' },
                pointLabels: { color: '#1c1917', font: { size: 11, weight: '600' } },
                ticks: { display: false },
              },
            },
          },
        });
      },
    }));
  });

  /* Global handle — page sends payload via this method, partial listens. */
  function _getDrawer() {
    if (window.__athlynkVolumeDrawer) return window.__athlynkVolumeDrawer;
    if (typeof Alpine !== 'undefined') {
      const el = document.getElementById('athlynk-volume-root');
      if (el) {
        try { return Alpine.$data(el); } catch (_) { /* */ }
      }
    }
    return null;
  }

  /* Normalize legacy positional call:
   *   AthlynkVolume.open(planId, planKind, durationWeeks)
   * into payload object form. */
  function _normalize(args) {
    if (args.length === 1 && typeof args[0] === 'object' && args[0] !== null) {
      return args[0];
    }
    if (args.length >= 1 && (typeof args[0] === 'number' || typeof args[0] === 'string')) {
      return {
        planId: args[0],
        planKind: args[1] || 'WEEKLY',
        durationWeeks: args[2] || 1,
      };
    }
    return {};
  }

  function _call(method, payload) {
    const drawer = _getDrawer();
    if (!drawer) {
      console.warn('[AthlynkVolume] drawer not ready; deferring');
      setTimeout(() => {
        const d = _getDrawer();
        if (d && typeof d[method] === 'function') d[method](payload);
        else console.error('[AthlynkVolume] drawer never initialized');
      }, 50);
      return;
    }
    drawer[method](payload);
  }

  window.AthlynkVolume = {
    open(...args)    { _call('handleOpen',    _normalize(args)); },
    refresh(...args) { _call('handleRefresh', _normalize(args)); },
    close()          { const d = _getDrawer(); if (d) d.close(); },
  };
})();
