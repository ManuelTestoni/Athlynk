/**
 * Athlynk · Single-Exercise Trend Drawer
 *
 * Slide-over that tracks one planned exercise slot over time from the athlete's
 * real logged sets. Mirrors the volume-analytics drawer's look (.va-* classes)
 * and chart styling so it reads as the same Athlynk tile.
 *
 * Open with: `AthlynkExerciseTrend.open(workoutExerciseId, exerciseName)`.
 * Data comes from `/api/allenamenti/esercizio/<id>/andamento/`:
 *   { exercise:{name, load_unit}, has_data, sessions:[{
 *       session_id, date, datetime, notes, avg_rpe,
 *       volume, top_set, weighted_avg_load, load_unit,
 *       sets:[{set_number, reps, load, load_unit, rpe, is_extra, substituted, actual_exercise}]
 *   }] }
 *
 * Two views: Sessione (1 point per session, default) and Serie (sets of one
 * picked session). Two metrics: Volume (volume load) and Carico (top set).
 */
(function () {
  // Metric-driven accent — volume reads primary blue, load a distinct cyan-slate.
  const C_VOLUME = '#1E3A5F';
  const C_LOAD = '#3F7690';

  function _hexA(hex, a) {
    const h = hex.replace('#', '');
    const r = parseInt(h.slice(0, 2), 16);
    const g = parseInt(h.slice(2, 4), 16);
    const b = parseInt(h.slice(4, 6), 16);
    return `rgba(${r}, ${g}, ${b}, ${Math.max(0, Math.min(1, a))})`;
  }

  function _fmtDate(iso) {
    if (!iso) return '—';
    try {
      return new Date(iso + 'T00:00:00').toLocaleDateString('it-IT', { day: '2-digit', month: 'short' });
    } catch (_) { return iso; }
  }

  function _fmtDateLong(iso) {
    if (!iso) return '—';
    try {
      return new Date(iso + 'T00:00:00').toLocaleDateString('it-IT', { weekday: 'long', day: 'numeric', month: 'long' });
    } catch (_) { return iso; }
  }

  function _fmtNum(v) {
    if (v === null || v === undefined) return '—';
    const n = +v;
    return Number.isInteger(n) ? String(n) : n.toFixed(1);
  }

  document.addEventListener('alpine:init', () => {
    Alpine.data('exerciseTrend', () => {
    // Chart.js instance kept OUTSIDE Alpine's reactive data — wrapping a live
    // chart in Alpine's Proxy breaks `.update()` (same pitfall as the volume +
    // client-check charts).
    let _chart = null;
    return {
      /* lifecycle */
      isOpen: false,
      loading: false,
      error: false,
      weId: null,
      exerciseName: '',
      exerciseUnit: 'KG',

      /* data */
      sessions: [],
      hasData: false,

      /* UI state */
      metric: 'volume',          // 'volume' | 'load'
      view: 'session',           // 'session' | 'series'  (client default: session)
      selectedSessionId: null,
      pointClicked: false,       // session-view detail opens only after a point tap
      _canvas: null,

      init() {
        window.__athlynkExerciseTrend = this;
        window.addEventListener('keydown', (e) => {
          if (e.key === 'Escape' && this.isOpen) this.close();
        });
      },

      /* === lifecycle === */
      open(weId, name) {
        this._openUrl(`/api/allenamenti/esercizio/${weId}/andamento/`, name, weId);
      },

      /* History-based open: works for any exercise ever performed (also
         substituted/added movements not present in the current plan). */
      openByName(name) {
        this._openUrl(`/api/allenamenti/esercizi/andamento-per-nome/?name=${encodeURIComponent(name)}`, name, null);
      },

      _openUrl(url, name, weId) {
        this.weId = weId;
        this.exerciseName = name || 'Esercizio';
        this.metric = 'volume';
        this.view = 'session';
        this.selectedSessionId = null;
        this.pointClicked = false;
        this.sessions = [];
        this.hasData = false;
        this.error = false;
        this.loading = true;
        if (!this.isOpen) window.panelLock && window.panelLock.acquire();
        this.isOpen = true;

        fetch(url, { credentials: 'same-origin' })
          .then(r => r.ok ? r.json() : Promise.reject(r.status))
          .then(d => {
            this.exerciseName = (d.exercise && d.exercise.name) || this.exerciseName;
            this.exerciseUnit = (d.exercise && d.exercise.load_unit) || 'KG';
            this.sessions = d.sessions || [];
            this.hasData = !!d.has_data;
            // Default the picked session (Serie view + detail) to the latest one.
            if (this.sessions.length) {
              this.selectedSessionId = this.sessions[this.sessions.length - 1].session_id;
            }
            this.loading = false;
            // Render after the slide settles so the canvas has a measurable size.
            setTimeout(() => { if (this.isOpen && this.hasData) this.renderChart(); }, 360);
          })
          .catch(err => {
            console.error('[AthlynkExerciseTrend] load failed', err);
            this.loading = false;
            this.error = true;
          });
      },

      close() {
        if (this.isOpen) window.panelLock && window.panelLock.release();
        this.isOpen = false;
        this._destroyChart();
      },

      /* === interaction === */
      setMetric(m) {
        if (this.metric === m) return;
        this.metric = m;
        this.renderChart();
      },
      setView(v) {
        if (this.view === v) return;
        this.view = v;
        // Back to the timeline → collapse the per-session detail until next tap.
        if (v === 'session') this.pointClicked = false;
        // Entering Serie with nothing picked → default to the latest session.
        if (v === 'series' && !this.selectedSessionId && this.sessions.length) {
          this.selectedSessionId = this.sessions[this.sessions.length - 1].session_id;
        }
        this.renderChart();
      },
      selectSession(id) {
        this.selectedSessionId = id;
        this.renderChart();
      },

      /* === derived === */
      mountCanvas(el) { this._canvas = el; },
      get selectedSession() {
        return this.sessions.find(s => s.session_id === this.selectedSessionId) || null;
      },
      accent() { return this.metric === 'volume' ? C_VOLUME : C_LOAD; },
      unit() { return this.exerciseUnit || 'KG'; },
      metricLabel() { return this.metric === 'volume' ? 'Volume' : 'Carico'; },
      metricValueOf(s) { return this.metric === 'volume' ? s.volume : s.top_set; },
      fmtDate: _fmtDate,
      fmtDateLong: _fmtDateLong,
      fmtNum: _fmtNum,

      /* === chart === */
      _destroyChart() {
        if (_chart) { _chart.destroy(); _chart = null; }
      },

      _baseOpts(onClick) {
        return {
          responsive: true,
          maintainAspectRatio: false,
          animation: { duration: 600, easing: 'easeOutQuart' },
          onClick,
          plugins: {
            legend: { display: false },
            tooltip: {
              backgroundColor: 'rgba(11,29,58,0.92)',
              titleColor: '#FFFFFF',
              bodyColor: '#FFFFFF',
              padding: 10,
              cornerRadius: 6,
            },
          },
          scales: {
            x: { grid: { display: false }, ticks: { color: '#4B5D75', font: { size: 11 } } },
            y: { beginAtZero: true, grid: { color: 'rgba(75,93,117,0.12)' }, ticks: { color: '#4B5D75', font: { size: 11 } } },
          },
        };
      },

      renderChart() {
        this._destroyChart();
        if (!this._canvas) {
          setTimeout(() => { if (this.isOpen && this.hasData) this.renderChart(); }, 120);
          return;
        }
        if (typeof Chart === 'undefined' || !this.hasData) return;

        this._canvas.removeAttribute('width');
        this._canvas.removeAttribute('height');
        this._canvas.style.width = '';
        this._canvas.style.height = '';
        const ctx = this._canvas.getContext('2d');

        if (this.view === 'session') this._renderSession(ctx);
        else this._renderSeries(ctx);
      },

      _renderSession(ctx) {
        const color = this.accent();
        const unit = this.unit();
        const metricLabel = this.metricLabel();
        const labels = this.sessions.map(s => _fmtDate(s.date));
        const values = this.sessions.map(s => this.metricValueOf(s));
        const self = this;

        _chart = new Chart(ctx, {
          type: 'line',
          data: {
            labels,
            datasets: [{
              label: metricLabel,
              data: values,
              borderColor: color,
              backgroundColor: _hexA(color, 0.12),
              pointBackgroundColor: color,
              pointBorderColor: '#FFFFFF',
              pointBorderWidth: 1.5,
              pointRadius: 5,
              pointHoverRadius: 8,
              borderWidth: 2.5,
              tension: 0.32,
              fill: true,
              spanGaps: true,
            }],
          },
          options: {
            ...this._baseOpts((evt, els) => {
              if (els && els.length) {
                const s = self.sessions[els[0].index];
                if (s) { self.selectedSessionId = s.session_id; self.pointClicked = true; }
              }
            }),
            plugins: {
              legend: { display: false },
              tooltip: {
                backgroundColor: 'rgba(11,29,58,0.92)',
                titleColor: '#FFFFFF', bodyColor: '#FFFFFF',
                padding: 10, cornerRadius: 6,
                callbacks: {
                  label: (c) => {
                    const v = c.parsed.y;
                    const suffix = self.metric === 'volume' ? ` ${unit}·rip` : ` ${unit}`;
                    return `${metricLabel}: ${v == null ? '—' : _fmtNum(v)}${suffix}`;
                  },
                },
              },
            },
          },
        });
      },

      _renderSeries(ctx) {
        const s = this.selectedSession;
        const color = this.accent();
        const unit = this.unit();
        const self = this;
        const sets = (s ? s.sets : []).filter(st => st.load != null);
        const labels = sets.map(st => 'Serie ' + st.set_number);
        const values = sets.map(st => this.metric === 'volume'
          ? (st.reps != null ? st.reps * st.load : null)
          : st.load);

        _chart = new Chart(ctx, {
          type: 'bar',
          data: {
            labels,
            datasets: [{
              label: this.metricLabel(),
              data: values,
              backgroundColor: _hexA(color, 0.82),
              borderColor: color,
              borderWidth: 0,
              borderRadius: 6,
              borderSkipped: false,
              maxBarThickness: 38,
            }],
          },
          options: {
            ...this._baseOpts(null),
            plugins: {
              legend: { display: false },
              tooltip: {
                backgroundColor: 'rgba(11,29,58,0.92)',
                titleColor: '#FFFFFF', bodyColor: '#FFFFFF',
                padding: 10, cornerRadius: 6,
                callbacks: {
                  label: (c) => {
                    const st = sets[c.dataIndex];
                    if (!st) return '';
                    if (self.metric === 'volume') {
                      return `${st.reps ?? '—'} rip × ${_fmtNum(st.load)} ${unit} = ${_fmtNum(c.parsed.y)}`;
                    }
                    return `${_fmtNum(st.load)} ${unit} × ${st.reps ?? '—'} rip`;
                  },
                },
              },
            },
          },
        });
      },
    };
    });
  });

  /* Global handle — exercise rows call this, the partial listens via Alpine. */
  function _get() {
    if (window.__athlynkExerciseTrend) return window.__athlynkExerciseTrend;
    if (typeof Alpine !== 'undefined') {
      const el = document.getElementById('athlynk-exercise-trend-root');
      if (el) { try { return Alpine.$data(el); } catch (_) { /* */ } }
    }
    return null;
  }

  window.AthlynkExerciseTrend = {
    open(weId, name) {
      const d = _get();
      if (d) { d.open(weId, name); return; }
      setTimeout(() => { const x = _get(); if (x) x.open(weId, name); }, 50);
    },
    openByName(name) {
      const d = _get();
      if (d) { d.openByName(name); return; }
      setTimeout(() => { const x = _get(); if (x) x.openByName(name); }, 50);
    },
    close() { const d = _get(); if (d) d.close(); },
  };
})();
