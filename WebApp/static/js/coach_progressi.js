document.addEventListener('alpine:init', () => {
  Alpine.data('coachProgressi', () => ({
    activeTab: 'loads',
    tabs: [
      { key: 'loads', label: 'Progressioni Carichi' },
      { key: 'volume', label: 'Volume & Analytics' },
      { key: 'sessions', label: 'Storico Sessioni' },
      { key: 'media', label: 'Foto & Media' },
    ],

    kpi: {},
    exercisesInProgram: window.PROGRESS_INIT.exercises_in_program,

    loads: { exerciseId: '', range: 'all', series: [], progress_4w: null, empty: true, chart: null,
             metrics: { load: true, reps: false, rpe: false } },
    volume: { weeks: [], muscles: [], series: {}, chart: null },
    adherence: { series: [], chart: null },
    rpe: { series: [], chart: null },

    sessions: [],
    media: [],

    sessionModal: { open: false, data: null, sessionId: null },
    coachNoteText: '',

    lightbox: { open: false, media: null, comment: '' },

    urls: window.PROGRESS_INIT.urls,

    async init() {
      this.loadKpi();
      if (this.exercisesInProgram.length) {
        this.loads.exerciseId = this.exercisesInProgram[0].exercise_id;
      }
      this.loadTab('loads');
    },

    _csrf() {
      return document.cookie.split('; ').find(r => r.startsWith('csrftoken='))?.split('=')[1] || '';
    },

    async loadKpi() {
      try {
        const r = await fetch(this.urls.kpi);
        this.kpi = await r.json();
      } catch (e) { /* silent */ }
    },

    async loadTab(key) {
      if (key === 'loads') return this.loadLoads();
      if (key === 'volume') {
        await this.loadVolume();
        await this.loadAdherence();
        await this.loadRpe();
        return;
      }
      if (key === 'sessions') return this.loadSessions();
      if (key === 'media') return this.loadMedia();
    },

    async loadLoads() {
      const params = new URLSearchParams();
      if (this.loads.exerciseId) params.set('exercise_id', this.loads.exerciseId);
      if (this.loads.range) params.set('range', this.loads.range);
      try {
        const r = await fetch(`${this.urls.loads}?${params.toString()}`);
        const d = await r.json();
        this.loads.series = d.series || [];
        this.loads.progress_4w = d.progress_4w;
        this.loads.empty = !this.loads.series.length;
      } catch (e) {
        this.loads.empty = true;
        this.loads.series = [];
      }
      this.$nextTick(() => this.renderLoadsChart());
    },

    renderLoadsChart() {
      const ctx = document.getElementById('loadsChart');
      if (!ctx) return;
      const data = this.loads.series;
      const m = this.loads.metrics;
      const labels = data.map(d => d.date);
      const dsData = [data.map(d => d.load_max), data.map(d => d.reps_avg), data.map(d => d.rpe_avg)];
      const hidden = [!m.load, !m.reps, !m.rpe];

      // Switching exercise/range keeps the chart instance and animates the
      // transition (like the volume chart) instead of tearing it down.
      if (this.loads.chart) {
        const c = this.loads.chart;
        c.data.labels = labels;
        c.data.datasets.forEach((ds, i) => {
          ds.data = dsData[i];
          c.setDatasetVisibility(i, !hidden[i]);
        });
        c.update();
        return;
      }

      this.loads.chart = new Chart(ctx, {
        type: 'line',
        data: {
          labels,
          datasets: [
            { label: 'Carico max (kg)', data: dsData[0], borderColor: '#b8860b', backgroundColor: 'rgba(184,134,11,0.15)', borderWidth: 2, tension: .3, yAxisID: 'y', hidden: hidden[0] },
            { label: 'Rip medie', data: dsData[1], borderColor: '#0d9488', backgroundColor: 'rgba(13,148,136,0.1)', borderWidth: 2, tension: .3, yAxisID: 'y1', hidden: hidden[1] },
            { label: 'RPE medio', data: dsData[2], borderColor: '#dc2626', backgroundColor: 'rgba(220,38,38,0.1)', borderWidth: 2, tension: .3, yAxisID: 'y1', hidden: hidden[2] },
          ],
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          interaction: { mode: 'index', intersect: false },
          plugins: { legend: { display: false } },
          scales: {
            y: { type: 'linear', position: 'left', title: { display: true, text: 'kg' } },
            y1: { type: 'linear', position: 'right', title: { display: true, text: 'rip / RPE' }, grid: { drawOnChartArea: false } },
          },
        },
      });
    },

    // Metric toggles drive dataset visibility; persist across exercise changes.
    toggleMetric(key) {
      this.loads.metrics[key] = !this.loads.metrics[key];
      const c = this.loads.chart;
      if (!c) return;
      const idx = { load: 0, reps: 1, rpe: 2 }[key];
      c.setDatasetVisibility(idx, this.loads.metrics[key]);
      c.update();
    },

    async loadVolume() {
      try {
        const r = await fetch(this.urls.volume);
        const d = await r.json();
        this.volume.weeks = d.weeks || [];
        this.volume.muscles = d.muscles || [];
        this.volume.series = d.series || {};
      } catch (e) { /* silent */ }
      this.$nextTick(() => this.renderVolumeChart());
    },

    renderVolumeChart() {
      const ctx = document.getElementById('volumeChart');
      if (!ctx) return;
      if (this.volume.chart) this.volume.chart.destroy();
      const colors = ['#b8860b', '#0d9488', '#dc2626', '#7c3aed', '#0ea5e9', '#16a34a', '#f59e0b', '#ec4899', '#6366f1', '#84cc16', '#06b6d4'];
      // Same histogram language as the adherence chart (flat fill, rounded
      // top); only the per-muscle colour differs, as intended.
      const datasets = this.volume.muscles.map((m, i) => ({
        label: m,
        data: this.volume.series[m] || [],
        backgroundColor: colors[i % colors.length],
        borderRadius: 4,
        borderWidth: 0,
      }));
      this.volume.chart = new Chart(ctx, {
        type: 'bar',
        data: { labels: this.volume.weeks, datasets },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          scales: { x: { stacked: false }, y: { stacked: false, beginAtZero: true } },
        },
      });
    },

    async loadAdherence() {
      try {
        const r = await fetch(this.urls.adherence);
        const d = await r.json();
        this.adherence.series = d.series || [];
      } catch (e) { /* silent */ }
      this.$nextTick(() => this.renderAdherenceChart());
    },

    renderAdherenceChart() {
      const ctx = document.getElementById('adherenceChart');
      if (!ctx) return;
      if (this.adherence.chart) this.adherence.chart.destroy();
      const data = this.adherence.series;
      this.adherence.chart = new Chart(ctx, {
        type: 'bar',
        data: {
          labels: data.map(d => d.week),
          datasets: [{
            label: '% completate',
            data: data.map(d => d.pct),
            backgroundColor: data.map(d => d.pct >= 80 ? '#16a34a' : d.pct >= 50 ? '#f59e0b' : '#dc2626'),
            borderRadius: 4,
          }],
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          scales: { y: { beginAtZero: true, max: 100, ticks: { callback: v => v + '%' } } },
        },
      });
    },

    async loadRpe() {
      try {
        const r = await fetch(this.urls.rpe);
        const d = await r.json();
        this.rpe.series = d.series || [];
      } catch (e) { /* silent */ }
      this.$nextTick(() => this.renderRpeChart());
    },

    renderRpeChart() {
      const ctx = document.getElementById('rpeChart');
      if (!ctx) return;
      if (this.rpe.chart) this.rpe.chart.destroy();
      const data = this.rpe.series;
      this.rpe.chart = new Chart(ctx, {
        type: 'line',
        data: {
          labels: data.map(d => d.week),
          datasets: [{
            label: 'RPE medio',
            data: data.map(d => d.avg_rpe),
            borderColor: '#dc2626',
            backgroundColor: 'rgba(220,38,38,0.15)',
            borderWidth: 2,
            tension: .3,
          }],
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          scales: { y: { min: 0, max: 10 } },
        },
      });
    },

    async loadSessions() {
      try {
        const r = await fetch(this.urls.sessions);
        this.sessions = await r.json();
      } catch (e) { this.sessions = []; }
    },

    async loadMedia() {
      try {
        const r = await fetch(this.urls.media);
        this.media = await r.json();
      } catch (e) { this.media = []; }
    },

    async openSession(id) {
      this.sessionModal = { open: true, data: null, sessionId: id };
      try {
        const r = await fetch(this.urls.session_detail.replace('__SID__', id));
        this.sessionModal.data = await r.json();
      } catch (e) { /* silent */ }
    },

    async addCoachNote() {
      if (!this.coachNoteText.trim() || !this.sessionModal.sessionId) return;
      try {
        const r = await fetch(this.urls.coach_note.replace('__SID__', this.sessionModal.sessionId), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this._csrf() },
          body: JSON.stringify({ text: this.coachNoteText }),
        });
        if (r.ok) {
          const note = await r.json();
          this.sessionModal.data.coach_notes = [note, ...(this.sessionModal.data.coach_notes || [])];
          this.coachNoteText = '';
        }
      } catch (e) { /* silent */ }
    },

    openLightbox(m) {
      this.lightbox = { open: true, media: m, comment: m.coach_comment || '' };
    },

    async saveMediaComment() {
      if (!this.lightbox.media) return;
      try {
        const r = await fetch(this.urls.media_comment.replace('__MID__', this.lightbox.media.id), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this._csrf() },
          body: JSON.stringify({ comment: this.lightbox.comment }),
        });
        if (r.ok) {
          this.lightbox.media.coach_comment = this.lightbox.comment;
          this.lightbox.open = false;
        }
      } catch (e) { /* silent */ }
    },
  }));
});
