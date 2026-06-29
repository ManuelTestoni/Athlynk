/* Athlynk · Client macro food-log — meal-first flow
   Backs pages/nutrizione/client_piano_macro.html.
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

    // Add-meal panel
    addMealOpen: false,
    newMealName: '',
    showCustomMealInput: false,
    pendingMeal: null,   // {name} — meal slot created but no food yet

    // Search overlay
    searchOpen: false,
    searchMealName: '',
    q: '',
    results: [],
    searching: false,
    adding: false,
    addingFoodId: null,
    searchVisibleCount: 10,

    // History
    historyOpen: false,
    historyLoading: false,
    historyLoaded: false,
    history: [],
    historyDayOpen: {},
    historyWeekOffset: 0,
    historyHasOlder: false,
    historyIsLatest: true,
    historyWindowLabel: '',

    init() {
      if (this.isWeekly) {
        this.activeDay = JS_DAY[new Date().getDay()];
      }
      document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
          if (this.searchOpen) this.closeSearch();
          else if (this.addMealOpen) this.addMealOpen = false;
        }
      });
    },

    // ── day helpers ──────────────────────────────────────────────────────────
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

    // ── entry filtering ──────────────────────────────────────────────────────
    visibleEntries() {
      if (!this.isWeekly) return this.entries;
      return this.entries.filter(e => e.day_of_week === this.activeDay);
    },

    // ── meal groups ──────────────────────────────────────────────────────────
    mealGroups() {
      const seen = new Map();
      const order = [];
      for (const e of this.visibleEntries()) {
        const key = e.meal_name || '';
        if (!seen.has(key)) { seen.set(key, []); order.push(key); }
        seen.get(key).push(e);
      }
      if (this.pendingMeal && !seen.has(this.pendingMeal.name)) {
        seen.set(this.pendingMeal.name, []);
        order.push(this.pendingMeal.name);
      }
      return order.map(name => ({ name, entries: seen.get(name) }));
    },

    mealTotals(mealEntries) {
      const t = { kcal: 0, prot: 0, carb: 0, fat: 0 };
      mealEntries.forEach(e => {
        const m = this.entryMacros(e);
        t.kcal += m.kcal; t.prot += m.prot; t.carb += m.carb; t.fat += m.fat;
      });
      return t;
    },

    mealSummaryText(mealEntries) {
      if (!mealEntries.length) return '';
      const t = this.mealTotals(mealEntries);
      return this.r0(t.kcal) + ' kcal';
    },

    mealMacroBar(mealEntries) {
      const t = this.mealTotals(mealEntries);
      const pk = (t.prot || 0) * 4, ck = (t.carb || 0) * 4, fk = (t.fat || 0) * 9;
      const total = pk + ck + fk;
      if (!total) return { p: 0, c: 0, f: 0 };
      return {
        p: Math.round(pk / total * 100),
        c: Math.round(ck / total * 100),
        f: Math.round(fk / total * 100),
      };
    },

    // ── add meal panel ───────────────────────────────────────────────────────
    openAddMeal() {
      this.addMealOpen = true;
      this.newMealName = '';
      this.showCustomMealInput = false;
    },

    toggleCustomMealInput() {
      this.showCustomMealInput = !this.showCustomMealInput;
      if (this.showCustomMealInput) {
        this.$nextTick(() => {
          const inp = document.getElementById('new-meal-input');
          if (inp) inp.focus();
        });
      }
    },

    pickPreset(name) {
      this.confirmMealName(name);
    },

    confirmMealName(name) {
      const trimmed = (name || this.newMealName || '').trim();
      if (!trimmed) return;
      this.addMealOpen = false;
      this.newMealName = '';
      this.pendingMeal = { name: trimmed };
      this.openSearch(trimmed);
    },

    // ── search overlay ───────────────────────────────────────────────────────
    openSearch(mealName) {
      this.searchMealName = mealName;
      this.searchOpen = true;
      this.q = '';
      this.results = [];
      this.searchVisibleCount = 10;
      this.$nextTick(() => {
        const inp = document.getElementById('food-search-input');
        if (inp) inp.focus();
      });
    },

    closeSearch() {
      this.searchOpen = false;
      this.q = '';
      this.results = [];
      this.searchVisibleCount = 10;
      if (this.pendingMeal) {
        const name = this.pendingMeal.name;
        const hasEntries = this.entries.some(e =>
          (e.meal_name || '') === name &&
          (!this.isWeekly || e.day_of_week === this.activeDay)
        );
        if (!hasEntries) this.pendingMeal = null;
      }
    },

    async search() {
      const q = this.q.trim();
      if (q.length < 2) { this.results = []; return; }
      this.searching = true;
      this.searchVisibleCount = 10;
      try {
        const r = await fetch(INIT.urls.foodSearch + '?q=' + encodeURIComponent(q));
        this.results = (await r.json()).results || [];
      } catch (_) { this.results = []; }
      this.searching = false;
    },

    visibleResults() {
      return this.results.slice(0, this.searchVisibleCount);
    },

    loadMoreResults() {
      this.searchVisibleCount += 10;
    },

    foodMacroBar(food) {
      const pk = (food.protein || 0) * 4, ck = (food.carb || 0) * 4, fk = (food.fat || 0) * 9;
      const total = pk + ck + fk;
      if (!total) return { p: 0, c: 0, f: 0 };
      return {
        p: Math.round(pk / total * 100),
        c: Math.round(ck / total * 100),
        f: Math.round(fk / total * 100),
      };
    },

    async addFood(food) {
      if (this.adding) return;
      this.adding = true;
      this.addingFoodId = food.id;
      const mealName = this.searchMealName;
      try {
        const res = await fetch(INIT.urls.createPattern, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': csrfToken() },
          body: JSON.stringify({
            food_id: food.id,
            quantity_g: 100,
            meal_name: mealName,
            day_of_week: this.isWeekly ? this.activeDay : null,
          }),
        });
        const data = await res.json().catch(() => ({}));
        if (res.ok && data.entry) {
          this.entries.push({ ...data.entry, _busy: false, _timer: null });
          if (this.pendingMeal && this.pendingMeal.name === mealName) {
            this.pendingMeal = null;
          }
          this.q = '';
          this.results = [];
          this.toast('Aggiunto.');
        } else {
          this.toast(data.error || 'Errore.');
        }
      } catch (_) { this.toast('Errore di rete.'); }
      this.adding = false;
      this.addingFoodId = null;
    },

    // ── qty update ───────────────────────────────────────────────────────────
    queueQtyUpdate(entry) {
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
      } catch (_) { this.toast('Modifica non salvata.'); }
      entry._busy = false;
    },

    // ── remove entry ─────────────────────────────────────────────────────────
    async removeEntry(entry) {
      const ok = await window.alConfirm({
        icon: 'ph-trash',
        title: 'Rimuovere alimento?',
        subtitle: entry.food_name,
        confirmLabel: 'Rimuovi',
      });
      if (!ok) return;
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
      } catch (_) {
        this.entries.splice(i, 0, backup);
        this.toast('Rimozione non riuscita.');
      }
    },

    // ── remove whole meal ────────────────────────────────────────────────────
    async removeMeal(mealName) {
      const toRemove = this.visibleEntries().filter(e => (e.meal_name || '') === mealName);
      if (!toRemove.length) return;
      const n = toRemove.length;
      const ok = await window.alConfirm({
        icon: 'ph-fork-knife',
        title: 'Eliminare il pasto?',
        subtitle: `"${mealName}" · ${n} ${n === 1 ? 'alimento' : 'alimenti'}`,
        confirmLabel: 'Elimina',
      });
      if (!ok) return;
      const ids = new Set(toRemove.map(e => e.id));
      this.entries = this.entries.filter(e => !ids.has(e.id));
      await Promise.all(toRemove.map(entry =>
        fetch(INIT.urls.detailPattern.replace('__ID__', entry.id), {
          method: 'DELETE',
          headers: { 'X-CSRFToken': csrfToken() },
        }).catch(() => {})
      ));
      this.toast('Pasto rimosso.');
    },

    // ── live totals ──────────────────────────────────────────────────────────
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
    r1(n) { return Math.round((n || 0) * 10) / 10; },
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

    // ── history ──────────────────────────────────────────────────────────────
    async toggleHistory() {
      this.historyOpen = !this.historyOpen;
      if (this.historyOpen && !this.historyLoaded) await this.loadHistory();
    },
    async loadHistory(offset) {
      if (offset !== undefined) { this.historyWeekOffset = offset; this.historyDayOpen = {}; }
      this.historyLoading = true;
      try {
        const r = await fetch(INIT.urls.historyPattern + '?week_offset=' + this.historyWeekOffset);
        const data = await r.json();
        this.history = data.history || [];
        this.historyHasOlder = data.has_older || false;
        this.historyIsLatest = data.is_latest !== false;
        this.historyWindowLabel = data.window_label || '';
        this.historyLoaded = true;
      } catch (_) { this.toast('Errore nel caricamento dello storico.'); }
      this.historyLoading = false;
    },
    async historyPrev() { await this.loadHistory(this.historyWeekOffset + 1); },
    async historyNext() { await this.loadHistory(this.historyWeekOffset - 1); },
    toggleHistoryDay(dateStr) {
      this.historyDayOpen[dateStr] = !this.historyDayOpen[dateStr];
      this.historyDayOpen = { ...this.historyDayOpen };
    },
    isHistoryDayOpen(dateStr) { return !!this.historyDayOpen[dateStr]; },
    historyDayTotals(entries) {
      const t = { kcal: 0, prot: 0, carb: 0, fat: 0 };
      entries.forEach(e => {
        const q = parseFloat(e.quantity_g) || 0;
        t.kcal += (e.kcal_per_100g  || 0) * q / 100;
        t.prot += (e.protein_per_100g || 0) * q / 100;
        t.carb += (e.carb_per_100g  || 0) * q / 100;
        t.fat  += (e.fat_per_100g   || 0) * q / 100;
      });
      return t;
    },
    detailDayUrl(dateStr) {
      return (INIT.urls.detailDayPattern || '').replace('__DATE__', dateStr);
    },

    toast(msg) {
      try {
        if (window.Alpine && Alpine.store && Alpine.store('toasts')) {
          Alpine.store('toasts').push({ kind: 'info', msg });
        }
      } catch (_) {}
    },
  };
}

window.macroLog = macroLog;
