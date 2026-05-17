/**
 * Athlynk Chart.js wrapper.
 *
 * One init dispatcher (`mountChart`) with a locked palette + animation
 * defaults so every chart in the app speaks the same visual language:
 *   - volume   → aegean   (#1c4a52)
 *   - intensity→ bronze   (#8a6a3a)
 *   - fatigue  → danger   (#8a3a3a)
 *   - adherence→ success  (#3a8a5a)
 *
 * Kinds: bar-volume, line-progression, heatmap-rpe, stacked-intensity, bullet-target.
 *
 * Usage:
 *   const c = AthlynkCharts.mountChart(canvasEl, 'bar-volume', {
 *     labels: ['Petto','Dorso',...],
 *     values: [120, 90, ...],
 *   });
 *   // later, on data change:
 *   c.data.datasets[0].data = newValues; c.update('active');
 *   // teardown:
 *   AthlynkCharts.destroyChart(canvasEl);
 */
(function () {
  const PALETTE = {
    volume: '#1c4a52',
    volumeFill: 'rgba(28,74,82,0.10)',
    intensity: '#8a6a3a',
    intensityFill: 'rgba(138,106,58,0.10)',
    fatigue: '#8a3a3a',
    fatigueScale: (v) => `rgba(138, 58, 58, ${Math.max(0.10, Math.min(0.95, v))})`,
    adherence: '#3a8a5a',
    ink: '#14110d',
    inkLabel: '#5b554a',
    grid: 'rgba(91,85,74,0.12)',
    marble: '#ece5d6',
    parchment: '#f4efe4',
    zone: {
      tech: '#d8cfba',   // <60% (technique)
      ipert: '#8a6a3a',  // 60-75% (hypertrophy)
      forza: '#1c4a52',  // 75-85% (strength)
      picco: '#8a3a3a',  // >85% (peak)
    },
  };

  const MATRIX_PLUGIN_URL = 'https://cdn.jsdelivr.net/npm/chartjs-chart-matrix@2/dist/chartjs-chart-matrix.min.js';
  let _matrixPluginPromise = null;
  function ensureMatrixPlugin() {
    if (typeof Chart !== 'undefined' && Chart.controllers && Chart.controllers.matrix) {
      return Promise.resolve();
    }
    if (_matrixPluginPromise) return _matrixPluginPromise;
    _matrixPluginPromise = new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = MATRIX_PLUGIN_URL;
      s.async = true;
      s.onload = () => resolve();
      s.onerror = () => reject(new Error('Failed to load chartjs-chart-matrix'));
      document.head.appendChild(s);
    });
    return _matrixPluginPromise;
  }

  function baseTooltipOptions() {
    return {
      backgroundColor: PALETTE.ink,
      titleColor: PALETTE.parchment,
      bodyColor: PALETTE.parchment,
      padding: 10,
      cornerRadius: 6,
      titleFont: { family: 'Inter, sans-serif', weight: '600' },
      bodyFont: { family: 'JetBrains Mono, monospace' },
    };
  }

  function baseAnimation() {
    return {
      duration: 750,
      easing: 'easeOutQuart',
    };
  }

  function baseTransitions() {
    return {
      active: { animation: { duration: 600, easing: 'easeOutQuart' } },
      resize: { animation: { duration: 200 } },
    };
  }

  function baseScales(yLabel = '') {
    return {
      x: {
        grid: { display: false },
        ticks: {
          font: { family: 'JetBrains Mono, monospace', size: 11 },
          color: PALETTE.inkLabel,
        },
      },
      y: {
        beginAtZero: true,
        grid: { color: PALETTE.grid },
        ticks: {
          font: { family: 'JetBrains Mono, monospace', size: 11 },
          color: PALETTE.inkLabel,
          callback: (v) => yLabel ? `${v}` : v,
        },
      },
    };
  }

  // --- kind: bar-volume ---
  function mountBarVolume(canvas, data, opts) {
    return new Chart(canvas, {
      type: 'bar',
      data: {
        labels: data.labels || [],
        datasets: [{
          label: data.label || 'Volume',
          data: data.values || [],
          backgroundColor: PALETTE.volume,
          borderRadius: 4,
          maxBarThickness: 36,
        }],
      },
      options: Object.assign({
        responsive: true,
        maintainAspectRatio: false,
        animation: baseAnimation(),
        transitions: baseTransitions(),
        plugins: {
          legend: { display: false },
          tooltip: Object.assign(baseTooltipOptions(), {
            callbacks: { label: (ctx) => ` ${ctx.parsed.y} set` },
          }),
        },
        scales: baseScales(),
      }, opts || {}),
    });
  }

  // --- kind: line-progression ---
  function mountLineProgression(canvas, data, opts) {
    return new Chart(canvas, {
      type: 'line',
      data: {
        labels: data.labels || [],
        datasets: [{
          label: data.label || 'Progressione',
          data: data.values || [],
          borderColor: data.color || PALETTE.intensity,
          backgroundColor: data.fillColor || PALETTE.intensityFill,
          fill: true,
          borderWidth: 2.5,
          pointRadius: 4,
          pointHoverRadius: 6,
          pointBackgroundColor: data.color || PALETTE.intensity,
          tension: 0.35,
          spanGaps: true,
        }],
      },
      options: Object.assign({
        responsive: true,
        maintainAspectRatio: false,
        animation: baseAnimation(),
        transitions: baseTransitions(),
        plugins: {
          legend: { display: false },
          tooltip: Object.assign(baseTooltipOptions(), {
            callbacks: {
              label: (ctx) => ` ${ctx.parsed.y !== null ? ctx.parsed.y : '—'} ${data.unit || ''}`.trim(),
            },
          }),
        },
        scales: baseScales(),
      }, opts || {}),
    });
  }

  // --- kind: stacked-intensity ---
  // data.zones: { tech: [...weeks], ipert: [...], forza: [...], picco: [...] }
  function mountStackedIntensity(canvas, data, opts) {
    const labels = data.labels || [];
    const zones = data.zones || {};
    const datasets = [
      { key: 'tech', name: 'Tecnica' },
      { key: 'ipert', name: 'Ipertrofia' },
      { key: 'forza', name: 'Forza' },
      { key: 'picco', name: 'Picco' },
    ].map(z => ({
      label: z.name,
      data: zones[z.key] || [],
      backgroundColor: PALETTE.zone[z.key],
      borderRadius: 3,
      maxBarThickness: 28,
    }));
    return new Chart(canvas, {
      type: 'bar',
      data: { labels, datasets },
      options: Object.assign({
        responsive: true,
        maintainAspectRatio: false,
        animation: baseAnimation(),
        transitions: baseTransitions(),
        plugins: {
          legend: {
            display: true,
            position: 'bottom',
            labels: {
              boxWidth: 10,
              boxHeight: 10,
              padding: 12,
              color: PALETTE.inkLabel,
              font: { family: 'Inter, sans-serif', size: 11 },
            },
          },
          tooltip: Object.assign(baseTooltipOptions(), {
            callbacks: { label: (ctx) => ` ${ctx.dataset.label}: ${ctx.parsed.y} set` },
          }),
        },
        scales: {
          x: Object.assign(baseScales().x, { stacked: true }),
          y: Object.assign(baseScales().y, { stacked: true }),
        },
      }, opts || {}),
    });
  }

  // --- kind: heatmap-rpe (RPE per day × exercise) ---
  // data: { xLabels: [...], yLabels: [...], cells: [{x, y, v}, ...] } values 0–10
  async function mountHeatmapRPE(canvas, data, opts) {
    await ensureMatrixPlugin();
    const xLabels = data.xLabels || [];
    const yLabels = data.yLabels || [];
    const cells = data.cells || [];
    return new Chart(canvas, {
      type: 'matrix',
      data: {
        datasets: [{
          label: 'RPE',
          data: cells.map(c => ({
            x: xLabels[c.x] || c.x,
            y: yLabels[c.y] || c.y,
            v: c.v,
          })),
          backgroundColor: (ctx) => {
            const v = ctx.raw && ctx.raw.v;
            if (v === null || v === undefined) return 'rgba(220,215,200,0.25)';
            // 1..10 → 0.10..0.95 alpha on danger color
            const norm = Math.max(0, Math.min(1, (v - 4) / 6));
            return PALETTE.fatigueScale(0.10 + norm * 0.85);
          },
          borderColor: 'rgba(244,239,228,0.6)',
          borderWidth: 1,
          width: ({ chart }) => (chart.chartArea || {}).width / Math.max(xLabels.length, 1) - 4,
          height: ({ chart }) => (chart.chartArea || {}).height / Math.max(yLabels.length, 1) - 4,
        }],
      },
      options: Object.assign({
        responsive: true,
        maintainAspectRatio: false,
        animation: baseAnimation(),
        plugins: {
          legend: { display: false },
          tooltip: Object.assign(baseTooltipOptions(), {
            callbacks: {
              title: (items) => items[0].raw.y,
              label: (ctx) => ` ${ctx.raw.x} · RPE ${ctx.raw.v ?? '—'}`,
            },
          }),
        },
        scales: {
          x: {
            type: 'category',
            labels: xLabels,
            offset: true,
            grid: { display: false },
            ticks: {
              font: { family: 'JetBrains Mono, monospace', size: 10 },
              color: PALETTE.inkLabel,
            },
          },
          y: {
            type: 'category',
            labels: yLabels,
            offset: true,
            reverse: true,
            grid: { display: false },
            ticks: {
              font: { family: 'Inter, sans-serif', size: 10 },
              color: PALETTE.inkLabel,
            },
          },
        },
      }, opts || {}),
    });
  }

  // --- kind: bullet-target (single horizontal progress vs target) ---
  function mountBulletTarget(canvas, data, opts) {
    const value = data.value || 0;
    const target = data.target || 1;
    const pct = Math.max(0, Math.min(150, (value / target) * 100));
    const color = pct < 80 ? PALETTE.fatigue : pct < 110 ? PALETTE.intensity : PALETTE.adherence;
    return new Chart(canvas, {
      type: 'bar',
      data: {
        labels: [data.label || ''],
        datasets: [
          { label: 'Effettivo', data: [value], backgroundColor: color, borderRadius: 4 },
          { label: 'Target', data: [Math.max(0, target - value)], backgroundColor: PALETTE.marble, borderRadius: 4 },
        ],
      },
      options: Object.assign({
        indexAxis: 'y',
        responsive: true,
        maintainAspectRatio: false,
        animation: baseAnimation(),
        plugins: {
          legend: { display: false },
          tooltip: Object.assign(baseTooltipOptions(), {
            callbacks: { label: () => ` ${value} / ${target}` },
          }),
        },
        scales: {
          x: Object.assign(baseScales().x, { stacked: true }),
          y: Object.assign(baseScales().y, { stacked: true, display: false }),
        },
      }, opts || {}),
    });
  }

  // --- registry to keep refs by canvas ---
  const _registry = new WeakMap();

  function mountChart(canvas, kind, data, opts) {
    if (!canvas) return null;
    if (typeof Chart === 'undefined') return null;
    // destroy previous on same canvas
    const old = _registry.get(canvas);
    if (old) { try { old.destroy(); } catch (e) { /* ignore */ } }
    let chart;
    switch (kind) {
      case 'bar-volume':       chart = mountBarVolume(canvas, data, opts); break;
      case 'line-progression': chart = mountLineProgression(canvas, data, opts); break;
      case 'stacked-intensity':chart = mountStackedIntensity(canvas, data, opts); break;
      case 'heatmap-rpe':      return mountHeatmapRPE(canvas, data, opts).then(c => { _registry.set(canvas, c); return c; });
      case 'bullet-target':    chart = mountBulletTarget(canvas, data, opts); break;
      default: console.warn('AthlynkCharts: unknown kind', kind); return null;
    }
    _registry.set(canvas, chart);
    return chart;
  }

  function destroyChart(canvas) {
    if (!canvas) return;
    const c = _registry.get(canvas);
    if (c) { try { c.destroy(); } catch (e) { /* ignore */ } }
    _registry.delete(canvas);
  }

  function getChart(canvas) {
    return _registry.get(canvas) || null;
  }

  window.AthlynkCharts = {
    PALETTE,
    mountChart,
    destroyChart,
    getChart,
    ensureMatrixPlugin,
  };
})();
