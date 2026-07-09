/* Athlynk · Client macro food-log — meal-first flow
   Backs pages/nutrizione/client_piano_macro.html.
   Init payload comes from window.MACRO_LOG_INIT. */

function macroLog() {
  const INIT = window.MACRO_LOG_INIT || {};
  const JS_DAY = { 0: 'DOM', 1: 'LUN', 2: 'MAR', 3: 'MER', 4: 'GIO', 5: 'VEN', 6: 'SAB' };

  function csrfToken() {
    return window.csrfToken() || INIT.csrf || '';
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

    // Add-food slide-in panel (mirrors the coach wizard's food picker:
    // search + categorie + recenti)
    foodPanel: {
      open: false, mealKey: null, q: '', filter: 'all', activeCat: '',
      categories: [], results: [], searching: false, justAdded: null,
      hasMore: false, loadingMore: false,
    },
    adding: false,
    addingFoodId: null,

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
          if (this.foodPanel.open) this.closeFoodPanel();
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
      this.openFoodPanel(trimmed);
    },

    // ── add-food panel ───────────────────────────────────────────────────────
    openFoodPanel(mealName) {
      this.foodPanel.mealKey = mealName;
      this.foodPanel.q = ''; this.foodPanel.filter = 'all'; this.foodPanel.activeCat = '';
      this.foodPanel.results = []; this.foodPanel.open = true;
      this.foodPanelSearch(this.foodPanel.categories.length === 0);
    },

    closeFoodPanel() {
      this.foodPanel.open = false;
      if (this.pendingMeal) {
        const name = this.pendingMeal.name;
        const hasEntries = this.entries.some(e =>
          (e.meal_name || '') === name &&
          (!this.isWeekly || e.day_of_week === this.activeDay)
        );
        if (!hasEntries) this.pendingMeal = null;
      }
    },

    setFoodFilter(f) {
      this.foodPanel.filter = f; this.foodPanel.activeCat = '';
      if (f === 'cat') { this.foodPanel.results = []; this.foodPanelSearch(this.foodPanel.categories.length === 0); }
      else { this.foodPanelSearch(); }
    },

    pickFoodCat(cat) { this.foodPanel.activeCat = cat; this.foodPanelSearch(); },

    async foodPanelSearch(loadCats = false) {
      const p = this.foodPanel;
      if (p.filter === 'cat' && !p.activeCat && !loadCats) { p.results = []; return; }
      p.searching = true;
      const u = new URL(INIT.urls.foodSearch, window.location.origin);
      if (p.q) u.searchParams.set('q', p.q);
      if (p.filter === 'recent') u.searchParams.set('filter', 'recent');
      if (p.filter === 'cat' && p.activeCat) u.searchParams.set('cat', p.activeCat);
      if (loadCats) u.searchParams.set('include_cats', '1');
      try {
        const r = await fetch(u);
        const d = await r.json();
        p.results = d.results || [];
        p.hasMore = !!d.has_more;
        if (d.categories) p.categories = d.categories;
        if (p.filter === 'cat' && !p.activeCat) { p.results = []; p.hasMore = false; }
      } catch (e) { p.results = []; p.hasMore = false; }
      p.searching = false;
    },

    async foodPanelLoadMore() {
      const p = this.foodPanel;
      if (p.loadingMore || !p.hasMore || p.searching) return;
      if (p.filter === 'recent') return;
      if (p.filter === 'cat' && !p.activeCat) return;
      p.loadingMore = true;
      const u = new URL(INIT.urls.foodSearch, window.location.origin);
      if (p.q) u.searchParams.set('q', p.q);
      if (p.filter === 'cat' && p.activeCat) u.searchParams.set('cat', p.activeCat);
      u.searchParams.set('offset', p.results.length);
      try {
        const r = await fetch(u);
        const d = await r.json();
        p.results = p.results.concat(d.results || []);
        p.hasMore = !!d.has_more;
      } catch (e) { p.hasMore = false; }
      p.loadingMore = false;
    },

    onFoodScroll(e) {
      const el = e.target;
      if (el.scrollHeight - el.scrollTop - el.clientHeight < 140) this.foodPanelLoadMore();
    },

    async addFromPanel(food) {
      await this.addFood(food, this.foodPanel.mealKey);
      const id = food.id;
      this.foodPanel.justAdded = id;
      setTimeout(() => { if (this.foodPanel.justAdded === id) this.foodPanel.justAdded = null; }, 900);
    },

    async addFood(food, mealName) {
      if (this.adding) return;
      this.adding = true;
      this.addingFoodId = food.id;
      mealName = mealName || this.foodPanel.mealKey;
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
