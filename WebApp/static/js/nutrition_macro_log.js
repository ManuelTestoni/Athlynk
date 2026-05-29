/* Athlynk · Client macro food-log
   Backs pages/nutrizione/client_piano_macro.html. The coach sets macro targets;
   here the client logs the foods they actually eat and sees live totals vs target.
   Init payload comes from window.MACRO_LOG_INIT. */

function macroLog() {
  const INIT = window.MACRO_LOG_INIT || {};
  const JS_DAY = { 0: 'DOM', 1: 'LUN', 2: 'MAR', 3: 'MER', 4: 'GIO', 5: 'VEN', 6: 'SAB' };

  function csrfToken() {
    return document.cookie.split('; ').find(r => r.startsWith('csrftoken='))?.split('=')[1]
      || INIT.csrf || '';
  }

  return {
    isWeekly: !!INIT.isWeekly,
    targets: INIT.targets || { avg: { kcal: 0, prot: 0, carb: 0, fat: 0 }, days: [] },
    weekDays: INIT.weekDays || [],
    entries: (INIT.entries || []).map(e => ({ ...e, _busy: false, _timer: null })),
    activeDay: null,

    /* food search popover */
    q: '',
    results: [],
    searching: false,
    showResults: false,
    adding: false,

    init() {
      if (this.isWeekly) {
        const today = JS_DAY[new Date().getDay()];
        // Prefer today; fall back to the first day the coach gave a target.
        this.activeDay = today;
      }
    },

    /* ── targets / day helpers ── */
    dayLabel(code) {
      const d = this.weekDays.find(x => x.code === code);
      return d ? d.label : code;
    },
    currentTarget() {
      if (!this.isWeekly) {
        const a = this.targets.avg || {};
        return { kcal: a.kcal || 0, prot: a.prot || 0, carb: a.carb || 0, fat: a.fat || 0 };
      }
      const d = (this.targets.days || []).find(x => x.code === this.activeDay);
      if (!d) return { kcal: 0, prot: 0, carb: 0, fat: 0 };
      return { kcal: d.kcal || 0, prot: d.protein || 0, carb: d.carb || 0, fat: d.fat || 0 };
    },
    dayHasTarget(code) {
      const d = (this.targets.days || []).find(x => x.code === code);
      return !!(d && (d.kcal || d.protein || d.carb || d.fat));
    },
    dayLogged(code) {
      return this.entries.filter(e => e.day_of_week === code).length;
    },

    /* ── live totals ── */
    visibleEntries() {
      if (!this.isWeekly) return this.entries;
      return this.entries.filter(e => e.day_of_week === this.activeDay);
    },
    entryMacros(e) {
      const q = parseFloat(e.quantity_g) || 0;
      return {
        kcal: (e.kcal_per_100g || 0) * q / 100,
        prot: (e.protein_per_100g || 0) * q / 100,
        carb: (e.carb_per_100g || 0) * q / 100,
        fat: (e.fat_per_100g || 0) * q / 100,
      };
    },
    totals() {
      const t = { kcal: 0, prot: 0, carb: 0, fat: 0 };
      this.visibleEntries().forEach(e => {
        const m = this.entryMacros(e);
        t.kcal += m.kcal; t.prot += m.prot; t.carb += m.carb; t.fat += m.fat;
      });
      return t;
    },
    r0(n) { return Math.round(n || 0); },
    r1(n) { return (Math.round((n || 0) * 10) / 10); },
    pct(consumed, target) {
      if (!target || target <= 0) return 0;
      return Math.min(100, Math.round((consumed / target) * 100));
    },
    overPct(consumed, target) {
      if (!target || target <= 0) return false;
      return consumed > target;
    },
    remaining(consumed, target) {
      return Math.round((target || 0) - (consumed || 0));
    },
    barColor(consumed, target) {
      if (!target) return 'var(--al-rule)';
      const p = consumed / target;
      if (p > 1.08) return 'var(--al-danger)';
      if (p >= 0.92) return 'var(--al-bronze)';
      return 'var(--ml-accent, var(--al-bronze))';
    },

    /* ── food search ── */
    async search() {
      if (this.q.trim().length < 2) { this.results = []; this.showResults = false; return; }
      this.searching = true;
      try {
        const r = await fetch(INIT.urls.foodSearch + '?q=' + encodeURIComponent(this.q.trim()));
        const d = await r.json();
        this.results = d.results || [];
      } catch (e) { this.results = []; }
      this.searching = false;
      this.showResults = true;
    },
    clearSearch() {
      this.q = ''; this.results = []; this.showResults = false;
    },

    /* ── CRUD ── */
    async addFood(food) {
      if (this.adding) return;
      this.adding = true;
      try {
        const res = await fetch(INIT.urls.createPattern, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': csrfToken() },
          body: JSON.stringify({
            food_id: food.id,
            quantity_g: 100,
            day_of_week: this.isWeekly ? this.activeDay : null,
          }),
        });
        const data = await res.json().catch(() => ({}));
        if (res.ok && data.entry) {
          this.entries.push({ ...data.entry, _busy: false, _timer: null });
          this.clearSearch();
          this.toast('Alimento aggiunto.');
        } else {
          this.toast(data.error || 'Errore durante l\'aggiunta.');
        }
      } catch (e) {
        this.toast('Errore di rete.');
      }
      this.adding = false;
    },
    queueQtyUpdate(entry) {
      // Clamp non-positive values back to a sane minimum.
      if (entry.quantity_g === '' || entry.quantity_g === null) return;
      if (Number(entry.quantity_g) < 0) entry.quantity_g = 0;
      if (entry._timer) clearTimeout(entry._timer);
      entry._timer = setTimeout(() => this.commitQty(entry), 500);
    },
    async commitQty(entry) {
      const qty = Number(entry.quantity_g);
      if (!qty || qty <= 0) return;
      entry._busy = true;
      try {
        await fetch(INIT.urls.detailPattern.replace('__ID__', entry.id), {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': csrfToken() },
          body: JSON.stringify({ quantity_g: qty }),
        });
      } catch (e) {
        this.toast('Modifica non salvata.');
      }
      entry._busy = false;
    },
    async removeEntry(entry) {
      const i = this.entries.findIndex(e => e.id === entry.id);
      if (i < 0) return;
      const backup = this.entries[i];
      this.entries.splice(i, 1);
      try {
        const res = await fetch(INIT.urls.detailPattern.replace('__ID__', entry.id), {
          method: 'DELETE',
          headers: { 'X-CSRFToken': csrfToken() },
        });
        if (!res.ok) throw new Error();
        this.toast('Alimento rimosso.');
      } catch (e) {
        this.entries.splice(i, 0, backup); // restore on failure
        this.toast('Rimozione non riuscita.');
      }
    },

    toast(msg) {
      try {
        if (window.Alpine && Alpine.store && Alpine.store('toasts')) {
          Alpine.store('toasts').push({ kind: 'info', msg });
          return;
        }
      } catch (e) {}
    },
  };
}

window.macroLog = macroLog;
