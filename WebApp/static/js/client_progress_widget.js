document.addEventListener('alpine:init', () => {
  Alpine.data('clientProgressWidget', () => {
    // Chart.js instances live OUTSIDE Alpine's reactive data (see coach_progressi.js).
    const charts = { loads: null, volume: null };
    return {
      loading: true,
      hasLoads: false,
      hasVolume: false,

      async init() {
        await Promise.all([this.loadLoads(), this.loadVolume()]);
        this.loading = false;
      },

      async loadLoads() {
        try {
          const r = await fetch(window.CLIENT_PROGRESS_URLS.loads);
          const d = await r.json();
          const series = (d.series || []).filter(s => s.load_max !== null);
          this.hasLoads = series.length >= 2;
          if (!this.hasLoads) return;
          this.$nextTick(() => {
            const ctx = document.getElementById('myLoadsChart');
            if (!ctx) return;
            charts.loads = new Chart(ctx, {
              type: 'line',
              data: { labels: series.map(s => s.date), datasets: [{
                data: series.map(s => s.load_max), borderColor: '#1E3A5F',
                backgroundColor: 'rgba(30,58,95,0.12)', fill: true, tension: .3,
                pointRadius: 2, pointBackgroundColor: '#1E3A5F',
              }] },
              options: {
                responsive: true, maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: { y: { display: false }, x: { grid: { display: false } } },
              },
            });
          });
        } catch (e) { this.hasLoads = false; }
      },

      async loadVolume() {
        try {
          const r = await fetch(window.CLIENT_PROGRESS_URLS.volume);
          const d = await r.json();
          const weeks = d.weeks || [];
          const muscles = d.muscles || [];
          this.hasVolume = weeks.length >= 1 && muscles.length >= 1;
          if (!this.hasVolume) return;
          this.$nextTick(() => {
            const ctx = document.getElementById('myVolumeChart');
            if (!ctx) return;
            const colors = ['#9C4448', '#1E3A5F', '#8A6E5A', '#3F7690', '#4F7A6A', '#6A5482', '#5B89B6', '#2B6E6E', '#8A6A1E', '#4A5A8A'];
            charts.volume = new Chart(ctx, {
              type: 'bar',
              data: {
                labels: weeks,
                datasets: muscles.map((m, i) => ({
                  label: m, data: d.series[m] || [],
                  backgroundColor: colors[i % colors.length], borderRadius: 4, borderWidth: 0,
                })),
              },
              options: {
                responsive: true, maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: { x: { stacked: false }, y: { stacked: false, beginAtZero: true, display: false } },
              },
            });
          });
        } catch (e) { this.hasVolume = false; }
      },
    };
  });
});
