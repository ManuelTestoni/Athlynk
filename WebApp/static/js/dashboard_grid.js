/* Athlynk — customizable dashboard grid (coach + athlete).
 *
 * One Alpine component (`dashGrid`) drives the GridStack grid on both
 * dashboards. WordPress-style editing: "Personalizza" unlocks drag; widgets
 * are added from the palette drawer, removed from their chrome, resized only
 * through preset S/M/L labels (free resize is disabled — the server registry
 * maps labels to grid units). Every change autosaves (debounced PUT to
 * /dashboard/layout); array order is the canonical cross-platform order the
 * iOS apps render, so serialization always sorts by (y, x).
 *
 * Chart widgets use `dashLineChart`/`dashBarChart` below. The Chart.js
 * instance lives in the closure, never in Alpine reactive data — wrapping a
 * live chart in Alpine's Proxy breaks `.update()` (same pitfall documented in
 * coach_business_analytics.js).
 */
(function () {
  const AEGEAN = '#1E3A5F';
  const GOLD = '#FFE066';
  const INK_LABEL = '#4B5D75';
  const GRID_LINES = 'rgba(75,93,117,0.12)';

  document.addEventListener('alpine:init', () => {
    Alpine.data('dashGrid', () => ({
      editing: false,
      paletteOpen: false,
      saveState: '',           // '' | 'saving' | 'saved' | 'error'
      catalog: [],
      placedTypes: [],
      pinPicker: { open: false, el: null, loading: false, athletes: [], selected: [] },
      _grid: null,
      _saveTimer: null,

      init() {
        const catalogEl = this.$root.querySelector('[data-dash-catalog]');
        this.catalog = catalogEl ? JSON.parse(catalogEl.textContent) : [];

        const gridEl = this.$root.querySelector('.grid-stack');
        this._grid = GridStack.init({
          column: 12,
          cellHeight: 88,
          margin: 12,
          float: false,
          staticGrid: true,
          disableResize: true,
          animate: true,
          columnOpts: { breakpoints: [{ w: 768, c: 1 }] },
        }, gridEl);

        this._grid.on('change added removed', () => {
          if (this.editing) this.scheduleSave();
        });
        this.syncPlaced();
      },

      // ---- edit mode ----
      enterEdit() {
        this.editing = true;
        this._grid.setStatic(false);
        this.$root.classList.add('dash-editing');
      },
      exitEdit() {
        this.editing = false;
        this.paletteOpen = false;
        this._grid.setStatic(true);
        this.$root.classList.remove('dash-editing');
      },

      catalogEntry(type) {
        return this.catalog.find((c) => c.type === type);
      },
      syncPlaced() {
        this.placedTypes = [...this.$root.querySelectorAll('.grid-stack-item')]
          .map((el) => el.dataset.widgetType);
      },
      isPlaced(type) {
        return this.placedTypes.includes(type);
      },

      // ---- serialization + autosave ----
      serialize() {
        const items = [...this.$root.querySelectorAll('.grid-stack-item')]
          .map((el) => {
            const n = el.gridstackNode || {};
            let config = {};
            try { config = JSON.parse(el.dataset.widgetConfig || '{}'); } catch (e) { /* keep {} */ }
            return {
              id: n.id || el.getAttribute('gs-id') || `wg_${el.dataset.widgetType}`,
              type: el.dataset.widgetType,
              x: n.x ?? 0,
              y: n.y ?? 0,
              size: el.dataset.widgetSize || 'M',
              config,
            };
          })
          .sort((a, b) => (a.y - b.y) || (a.x - b.x));
        return { version: 1, widgets: items };
      },

      scheduleSave() {
        clearTimeout(this._saveTimer);
        this.saveState = 'saving';
        this._saveTimer = setTimeout(() => this.save(), 600);
      },

      async save() {
        try {
          const r = await fetch('/dashboard/layout', {
            method: 'PUT',
            credentials: 'same-origin',
            headers: {
              'Content-Type': 'application/json',
              'X-CSRFToken': window.csrfToken(),
            },
            body: JSON.stringify(this.serialize()),
          });
          if (!r.ok) throw new Error(`HTTP ${r.status}`);
          this.saveState = 'saved';
          setTimeout(() => { if (this.saveState === 'saved') this.saveState = ''; }, 2000);
        } catch (e) {
          this.saveState = 'error';
          window.toastError('Layout non salvato. Riprova.');
        }
      },

      // ---- add / remove / resize ----
      async addWidget(type) {
        if (this.isPlaced(type)) return;
        const entry = this.catalogEntry(type);
        if (!entry) return;
        try {
          const r = await fetch(`/dashboard/widget/${type}`, { credentials: 'same-origin' });
          if (!r.ok) throw new Error(`HTTP ${r.status}`);
          const data = await r.json();

          const el = document.createElement('div');
          el.className = 'grid-stack-item';
          el.dataset.widgetType = type;
          el.dataset.widgetSize = data.size;
          el.dataset.widgetSizes = (data.sizes || []).join(',');
          el.dataset.widgetConfig = '{}';
          el.setAttribute('gs-id', data.id);
          el.setAttribute('gs-w', data.w);
          el.setAttribute('gs-h', data.h);
          el.setAttribute('gs-no-resize', 'true');
          el.innerHTML = data.html;

          this.$root.querySelector('.grid-stack').appendChild(el);
          this._grid.makeWidget(el);
          Alpine.initTree(el);
          this.syncPlaced();
          this.paletteOpen = false;
        } catch (e) {
          window.toastError('Impossibile aggiungere il widget.');
        }
      },

      removeWidget(el) {
        if (!el) return;
        this._grid.removeWidget(el);
        this.syncPlaced();
      },

      setSize(el, size) {
        if (!el) return;
        const entry = this.catalogEntry(el.dataset.widgetType);
        const dims = entry && entry.sizes && entry.sizes[size];
        if (!dims) return;
        el.dataset.widgetSize = size;
        this._grid.update(el, { w: dims[0], h: dims[1] });
        this.scheduleSave();
      },

      async resetDefault() {
        if (!window.confirm('Ripristinare la dashboard predefinita?')) return;
        try {
          const r = await fetch('/dashboard/layout', {
            method: 'DELETE',
            credentials: 'same-origin',
            headers: { 'X-CSRFToken': window.csrfToken() },
          });
          if (!r.ok) throw new Error(`HTTP ${r.status}`);
          window.location.reload();
        } catch (e) {
          window.toastError('Ripristino non riuscito. Riprova.');
        }
      },

      // ---- pinned athletes configuration (coach only) ----
      async openPinPicker(el) {
        let config = {};
        try { config = JSON.parse(el.dataset.widgetConfig || '{}'); } catch (e) { /* keep {} */ }
        this.pinPicker = {
          open: true, el, loading: true, athletes: [],
          selected: [...(config.client_ids || [])],
        };
        try {
          const r = await fetch('/dashboard/pinned-athletes?all=1', { credentials: 'same-origin' });
          if (!r.ok) throw new Error(`HTTP ${r.status}`);
          this.pinPicker.athletes = (await r.json()).athletes;
        } catch (e) {
          window.toastError('Impossibile caricare gli atleti.');
          this.pinPicker.open = false;
        } finally {
          this.pinPicker.loading = false;
        }
      },

      togglePin(id) {
        const sel = this.pinPicker.selected;
        const i = sel.indexOf(id);
        if (i >= 0) sel.splice(i, 1);
        else if (sel.length < 6) sel.push(id);
      },

      async savePins() {
        const el = this.pinPicker.el;
        if (!el) return;
        const config = { client_ids: [...this.pinPicker.selected] };
        el.dataset.widgetConfig = JSON.stringify(config);
        this.pinPicker.open = false;
        this.scheduleSave();
        // Re-render the widget body with the new selection.
        try {
          const qs = new URLSearchParams({
            size: el.dataset.widgetSize || 'M',
            config: JSON.stringify(config),
          });
          const r = await fetch(`/dashboard/widget/pinned_athletes?${qs}`, { credentials: 'same-origin' });
          if (!r.ok) throw new Error(`HTTP ${r.status}`);
          const data = await r.json();
          const content = el.querySelector('.grid-stack-item-content');
          if (content) {
            content.outerHTML = data.html;
            Alpine.initTree(el);
          }
        } catch (e) {
          window.toastError('Anteprima non aggiornata. Ricarica la pagina.');
        }
      },
    }));

    // ---- chart widgets ------------------------------------------------------
    const readData = (root) => {
      const s = root.querySelector('[data-chart-data]');
      try { return JSON.parse(s ? s.textContent : '{}'); } catch (e) { return {}; }
    };

    Alpine.data('dashLineChart', () => {
      let chart = null;
      return {
        init() {
          const d = readData(this.$root);
          if (!d.labels || !window.Chart) return;
          const currency = this.$root.dataset.chartKind === 'currency';
          chart = new Chart(this.$refs.canvas, {
            type: 'line',
            data: {
              labels: d.labels,
              datasets: [{
                data: d.values,
                borderColor: AEGEAN,
                backgroundColor: 'rgba(30,58,95,0.08)',
                fill: true,
                tension: 0.35,
                pointRadius: 0,
                pointHoverRadius: 4,
                pointHoverBackgroundColor: GOLD,
                borderWidth: 2,
              }],
            },
            options: {
              responsive: true,
              maintainAspectRatio: false,
              plugins: {
                legend: { display: false },
                tooltip: {
                  callbacks: currency
                    ? { label: (c) => '€' + Math.round(c.parsed.y) }
                    : {},
                },
              },
              scales: {
                x: { grid: { display: false }, ticks: { color: INK_LABEL, maxTicksLimit: 6 } },
                y: {
                  grid: { color: GRID_LINES },
                  ticks: {
                    color: INK_LABEL,
                    maxTicksLimit: 5,
                    callback: currency ? (v) => '€' + v : undefined,
                  },
                },
              },
            },
          });
        },
        destroy() { if (chart) { chart.destroy(); chart = null; } },
      };
    });

    // Athlete progress widgets: same data/rendering as the pre-grid
    // clientProgressWidget, but one component per widget so each can live in
    // its own grid item (endpoint URL comes from data-url on the root).
    Alpine.data('dashLoadsWidget', () => {
      let chart = null;
      return {
        loading: true,
        hasData: false,
        async init() {
          try {
            const r = await fetch(this.$root.dataset.url, { credentials: 'same-origin' });
            const d = await r.json();
            const series = (d.series || []).filter((s) => s.load_max !== null);
            this.hasData = series.length >= 2;
            if (!this.hasData) return;
            this.$nextTick(() => {
              if (chart) chart.destroy();
              chart = new Chart(this.$refs.canvas, {
                type: 'line',
                data: { labels: series.map((s) => s.date), datasets: [{
                  data: series.map((s) => s.load_max), borderColor: AEGEAN,
                  backgroundColor: 'rgba(30,58,95,0.12)', fill: true, tension: 0.3,
                  pointRadius: 2, pointBackgroundColor: AEGEAN,
                }] },
                options: {
                  responsive: true, maintainAspectRatio: false,
                  plugins: { legend: { display: false } },
                  scales: { y: { display: false }, x: { grid: { display: false } } },
                },
              });
            });
          } catch (e) { this.hasData = false; }
          finally { this.loading = false; }
        },
        destroy() { if (chart) { chart.destroy(); chart = null; } },
      };
    });

    Alpine.data('dashVolumeWidget', () => {
      let chart = null;
      const COLORS = ['#9C4448', '#1E3A5F', '#8A6E5A', '#3F7690', '#4F7A6A',
                      '#6A5482', '#5B89B6', '#2B6E6E', '#8A6A1E', '#4A5A8A'];
      return {
        loading: true,
        hasData: false,
        async init() {
          try {
            const r = await fetch(this.$root.dataset.url, { credentials: 'same-origin' });
            const d = await r.json();
            const weeks = d.weeks || [];
            const muscles = d.muscles || [];
            this.hasData = weeks.length >= 1 && muscles.length >= 1;
            if (!this.hasData) return;
            this.$nextTick(() => {
              if (chart) chart.destroy();
              chart = new Chart(this.$refs.canvas, {
                type: 'bar',
                data: {
                  labels: weeks,
                  datasets: muscles.map((m, i) => ({
                    label: m, data: d.series[m] || [],
                    backgroundColor: COLORS[i % COLORS.length], borderRadius: 4, borderWidth: 0,
                  })),
                },
                options: {
                  responsive: true, maintainAspectRatio: false,
                  plugins: { legend: { display: false } },
                  scales: { x: { stacked: false }, y: { stacked: false, beginAtZero: true, display: false } },
                },
              });
            });
          } catch (e) { this.hasData = false; }
          finally { this.loading = false; }
        },
        destroy() { if (chart) { chart.destroy(); chart = null; } },
      };
    });

    Alpine.data('dashBarChart', () => {
      let chart = null;
      return {
        init() {
          const d = readData(this.$root);
          if (!d.labels || !window.Chart) return;
          chart = new Chart(this.$refs.canvas, {
            type: 'bar',
            data: {
              labels: d.labels,
              datasets: [{
                data: d.values,
                backgroundColor: 'rgba(30,58,95,0.75)',
                hoverBackgroundColor: AEGEAN,
                borderRadius: 6,
                maxBarThickness: 28,
              }],
            },
            options: {
              responsive: true,
              maintainAspectRatio: false,
              plugins: { legend: { display: false } },
              scales: {
                x: { grid: { display: false }, ticks: { color: INK_LABEL } },
                y: { grid: { color: GRID_LINES }, ticks: { color: INK_LABEL, precision: 0, maxTicksLimit: 5 } },
              },
            },
          });
        },
        destroy() { if (chart) { chart.destroy(); chart = null; } },
      };
    });
  });
})();
