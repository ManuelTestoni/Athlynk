/* Athlynk · Nutrition Wizard · Charts mixin
   Pure SVG, no deps. Donut + histogram helpers. Merged into wizard via Object.assign. */

function nutritionWizardChartsMixin() {
  return {
    /* === day-report modal state (WEEKLY) === */
    dayReportOpen: false,
    dayReportCode: null,

    /* === histogram toggles (WEEKLY Media) === */
    histoShow: { protein: false, carb: false, fat: false },

    openDayReport(code) {
      this.dayReportCode = code;
      this.dayReportOpen = true;
    },
    closeDayReport() {
      this.dayReportOpen = false;
      this.dayReportCode = null;
    },
    toggleHisto(key) {
      this.histoShow[key] = !this.histoShow[key];
    },

    /* === macro pie / donut === */
    /* segments[]: { key, label, kcal, pct, color, start, end } */
    macroPieSegments(protein, carb, fat) {
      const pK = (protein || 0) * 4;
      const cK = (carb || 0) * 4;
      const fK = (fat || 0) * 9;
      const total = pK + cK + fK;
      const PALETTE = {
        protein: 'var(--al-aegean)',
        carb:    'var(--al-bronze)',
        fat:     'var(--al-ink-mute)',
      };
      const raw = [
        { key: 'protein', label: 'Proteine',    grams: Math.round(protein || 0), kcal: Math.round(pK), color: PALETTE.protein },
        { key: 'carb',    label: 'Carboidrati', grams: Math.round(carb || 0),    kcal: Math.round(cK), color: PALETTE.carb },
        { key: 'fat',     label: 'Grassi',      grams: Math.round(fat || 0),     kcal: Math.round(fK), color: PALETTE.fat },
      ];
      if (!total) {
        return raw.map(r => ({ ...r, pct: 0, start: 0, end: 0 }));
      }
      let cum = 0;
      return raw.map(r => {
        const pct = r.kcal / total;
        const start = cum;
        cum += pct;
        return { ...r, pct, start, end: cum };
      });
    },

    /* SVG donut path. start/end as fractions 0..1, centered (cx,cy), radii rOuter/rInner. */
    donutPath(start, end, cx, cy, rOuter, rInner) {
      if (end <= start) return '';
      /* full circle workaround */
      if (end - start >= 0.9999) {
        return `M ${cx - rOuter},${cy} A ${rOuter},${rOuter} 0 1 0 ${cx + rOuter},${cy} A ${rOuter},${rOuter} 0 1 0 ${cx - rOuter},${cy} M ${cx - rInner},${cy} A ${rInner},${rInner} 0 1 1 ${cx + rInner},${cy} A ${rInner},${rInner} 0 1 1 ${cx - rInner},${cy} Z`;
      }
      const a0 = start * 2 * Math.PI - Math.PI / 2;
      const a1 = end   * 2 * Math.PI - Math.PI / 2;
      const x0o = cx + rOuter * Math.cos(a0);
      const y0o = cy + rOuter * Math.sin(a0);
      const x1o = cx + rOuter * Math.cos(a1);
      const y1o = cy + rOuter * Math.sin(a1);
      const x0i = cx + rInner * Math.cos(a0);
      const y0i = cy + rInner * Math.sin(a0);
      const x1i = cx + rInner * Math.cos(a1);
      const y1i = cy + rInner * Math.sin(a1);
      const large = (end - start) > 0.5 ? 1 : 0;
      return `M ${x0o},${y0o} A ${rOuter},${rOuter} 0 ${large} 1 ${x1o},${y1o} L ${x1i},${y1i} A ${rInner},${rInner} 0 ${large} 0 ${x0i},${y0i} Z`;
    },

    /* Pie data shortcuts using wizard state */
    dailyPieSegments() {
      return this.macroPieSegments(this.totalMacro('protein'), this.totalMacro('carb'), this.totalMacro('fat'));
    },
    weeklyDayPieSegments(code) {
      return this.macroPieSegments(
        this.dayMacro(code, 'protein'),
        this.dayMacro(code, 'carb'),
        this.dayMacro(code, 'fat'),
      );
    },

    pieKcalTotal(segments) {
      return segments.reduce((s, x) => s + x.kcal, 0);
    },
    pctLabel(p) {
      return Math.round(p * 100) + '%';
    },

    /* === histogram (WEEKLY all days) === */
    weekChartData() {
      return this.weekDays.map(d => ({
        code: d.code,
        label: d.label,
        kcal: this.dayKcal(d.code),
        protein: this.dayMacro(d.code, 'protein'),
        carb:    this.dayMacro(d.code, 'carb'),
        fat:     this.dayMacro(d.code, 'fat'),
      }));
    },
    weekChartMaxKcal() {
      const vals = this.weekChartData().map(d => d.kcal);
      const m = Math.max.apply(null, vals);
      return m > 0 ? m : 1;
    },
    /* Macro values converted to kcal so they share scale with kcal bars */
    macroToKcal(grams, key) {
      const factor = key === 'fat' ? 9 : 4;
      return grams * factor;
    },
    weekChartMaxAll() {
      let m = this.weekChartMaxKcal();
      const data = this.weekChartData();
      ['protein','carb','fat'].forEach(k => {
        if (!this.histoShow[k]) return;
        data.forEach(d => {
          const v = this.macroToKcal(d[k], k);
          if (v > m) m = v;
        });
      });
      return m > 0 ? m : 1;
    },
    histoBarHeight(value, max, maxPx) {
      if (!max) return 0;
      return Math.round((value / max) * maxPx);
    },
    histoActiveCount() {
      return ['protein','carb','fat'].filter(k => this.histoShow[k]).length;
    },
  };
}

window.nutritionWizardChartsMixin = nutritionWizardChartsMixin;
