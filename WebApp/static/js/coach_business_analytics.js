/* Coach business-analytics dashboard.
 *
 * Fetches the nightly rollups from /api/v1/coach/analytics/{business,risk}
 * (dual-auth: the session cookie authenticates the same endpoints the iOS app
 * hits with a Bearer token) and renders KPI tiles, a 30-day trend and the
 * at-risk client table with explained reason codes.
 *
 * The Chart.js instance lives in THIS closure, never inside Alpine's reactive
 * data — wrapping a live chart in Alpine's Proxy breaks `.update()` (Chart
 * mutates deep internals during its animation loop). Same pitfall as
 * volume_analytics.js. Create/destroy through the proxy is fine; in-place
 * update is not — so keep it local.
 */
(function () {
  let _trendChart = null;

  const AEGEAN = '#1E3A5F';
  const HIGHLIGHT = '#FFE066';
  const INK_LABEL = '#4B5D75';
  const GRID = 'rgba(75,93,117,0.12)';

  const KPI_DEFS = [
    { key: 'active_clients_count', label: 'Atleti attivi', icon: 'ph-users', fmt: 'int', meta: 'In carico' },
    { key: 'at_risk_clients_count', label: 'A rischio', icon: 'ph-warning', fmt: 'int', meta: 'Medio/alto' },
    { key: 'renewals_due_7d', label: 'Rinnovi 7gg', icon: 'ph-calendar-check', fmt: 'int', meta: 'In scadenza' },
    { key: 'churn_rate_30d', label: 'Churn 30gg', icon: 'ph-trend-down', fmt: 'pct', meta: 'Tasso abbandono' },
    { key: 'monthly_revenue', label: 'Ricavo attivo', icon: 'ph-currency-eur', fmt: 'eur', meta: 'Abbonamenti attivi' },
    { key: 'revenue_per_active_client', label: 'Ricavo / atleta', icon: 'ph-coins', fmt: 'eur', meta: 'Media' },
    { key: 'sla_adherence_rate', label: 'Aderenza SLA', icon: 'ph-clock', fmt: 'pct', meta: 'Risposte in tempo' },
    { key: 'backlog_open_reviews', label: 'Check da rivedere', icon: 'ph-clipboard-text', fmt: 'int', meta: 'Arretrato' },
  ];

  const TREND_LABELS = {
    at_risk_clients_count: 'Clienti a rischio',
    active_clients_count: 'Atleti attivi',
    avg_risk_score: 'Risk score medio',
  };

  function fmtValue(v, fmt) {
    if (v === null || v === undefined) return '—';
    if (fmt === 'pct') return (Math.round(v * 10) / 10) + '%';
    if (fmt === 'eur') return '€' + Math.round(v);
    return v;
  }

  document.addEventListener('alpine:init', () => {
    Alpine.data('coachBusinessAnalytics', () => ({
      loading: true,
      hasData: false,
      snapshotDate: null,
      kpis: {},
      series: [],
      kpiCards: [],
      riskClients: [],
      riskHasMore: false,
      riskLoadingMore: false,
      riskBreakdownData: { all: 0, high: 0, medium: 0, low: 0 },
      riskFilter: 'all',
      trendMetric: 'at_risk_clients_count',

      async init() {
        await Promise.all([this.loadBusiness(), this.loadRisk('all', 0)]);
        this.loading = false;
        if (this.hasData) {
          this.$nextTick(() => this.renderTrend());
        }
      },

      async loadBusiness() {
        try {
          const r = await fetch('/api/v1/coach/analytics/business', { credentials: 'same-origin' });
          const data = await r.json();
          this.kpis = data.kpis || {};
          this.series = data.series || [];
          this.snapshotDate = data.snapshot_date;
          this.kpiCards = KPI_DEFS.map(d => ({
            key: d.key, label: d.label, icon: d.icon, meta: d.meta,
            value: fmtValue(this.kpis[d.key], d.fmt),
          }));
          if (this.snapshotDate) this.hasData = true;
        } catch (e) { /* leave empty state */ }
      },

      async loadRisk(cls, offset) {
        cls = cls ?? this.riskFilter;
        offset = offset ?? 0;
        try {
          const r = await fetch(`/api/v1/coach/analytics/risk?class=${cls}&offset=${offset}`, { credentials: 'same-origin' });
          const data = await r.json();
          if (offset === 0) {
            this.riskClients = data.clients || [];
          } else {
            this.riskClients = this.riskClients.concat(data.clients || []);
          }
          this.riskHasMore = data.has_more || false;
          this.riskBreakdownData = data.breakdown || { all: 0, high: 0, medium: 0, low: 0 };
          if (data.snapshot_date) this.hasData = true;
        } catch (e) { /* ignore */ }
      },
      async loadMoreRisk() {
        this.riskLoadingMore = true;
        await this.loadRisk(this.riskFilter, this.riskClients.length);
        this.riskLoadingMore = false;
      },

      get riskBreakdown() {
        const bd = this.riskBreakdownData;
        return [
          { cls: 'all',    label: 'Tutti',  count: bd.all,    dot: '#7C8CA3' },
          { cls: 'high',   label: 'Alto',   count: bd.high,   dot: '#A23B3B' },
          { cls: 'medium', label: 'Medio',  count: bd.medium, dot: '#8A6A1E' },
          { cls: 'low',    label: 'Basso',  count: bd.low,    dot: '#3F7A5E' },
        ];
      },

      get riskFilterLabel() {
        return { high: 'Alto', medium: 'Medio', low: 'Basso', all: 'Tutti' }[this.riskFilter];
      },

      async setRiskFilter(cls) { this.riskFilter = cls; await this.loadRisk(cls, 0); },

      setTrend(metric) {
        this.trendMetric = metric;
        this.renderTrend();
      },

      renderTrend() {
        const canvas = document.getElementById('businessTrendChart');
        if (!canvas || !window.Chart) return;
        if (_trendChart) { _trendChart.destroy(); _trendChart = null; }
        const labels = this.series.map(p => p.snapshot_date.slice(5));  // MM-DD
        const values = this.series.map(p => p[this.trendMetric]);
        _trendChart = new Chart(canvas, {
          type: 'line',
          data: {
            labels,
            datasets: [{
              label: TREND_LABELS[this.trendMetric] || this.trendMetric,
              data: values,
              borderColor: AEGEAN,
              backgroundColor: 'rgba(30,58,95,0.10)',
              borderWidth: 2.5, tension: 0.35, fill: true,
              pointRadius: 2, pointHoverRadius: 5, pointBackgroundColor: HIGHLIGHT,
            }],
          },
          options: {
            responsive: true, maintainAspectRatio: false,
            plugins: { legend: { display: false } },
            scales: {
              x: { grid: { color: GRID }, ticks: { color: INK_LABEL, maxTicksLimit: 8 } },
              y: { grid: { color: GRID }, ticks: { color: INK_LABEL }, beginAtZero: true },
            },
          },
        });
      },

      initials(name) {
        return (name || '?').split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase();
      },
      riskLabel(cls) { return { high: 'Alto', medium: 'Medio', low: 'Basso' }[cls] || cls; },
      riskTagClass(cls) {
        return { high: 'al-badge al-badge-danger', medium: 'al-badge al-badge-warn',
                 low: 'al-badge al-badge-success' }[cls] || 'al-badge';
      },
    }));
  });
})();
