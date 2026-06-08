/* Percorso Timeline — Alpine.js component
 * A single horizontal axis. Every event is a collapsed dot sitting ON the
 * axis (no vertical scrolling). Click a dot to expand its card with an
 * animation; click again / elsewhere / Esc to collapse.
 *
 * View modes control how many months fit in the viewport — the data span
 * (≥ 1 year) is fixed; the track is rescaled and scrolls horizontally:
 *   anno      → ~12 months per viewport (whole year visible)
 *   semestre  → ~6  months per viewport (first half shown, scroll for rest)
 *   mese      → ~1  month  per viewport (zoomed in, scroll through the year)
 *
 * Usage: x-data="percorsoTimeline({ apiUrl: '...' })"
 */
(function () {

  const MONTH_NAMES_IT   = ['Gen','Feb','Mar','Apr','Mag','Giu','Lug','Ago','Set','Ott','Nov','Dic'];
  const MONTH_NAMES_FULL = ['Gennaio','Febbraio','Marzo','Aprile','Maggio','Giugno','Luglio','Agosto','Settembre','Ottobre','Novembre','Dicembre'];

  const TYPE_META = {
    allenamento: { icon: 'ph-barbell',    label: 'Allenamento' },
    nutrizione:  { icon: 'ph-leaf',       label: 'Nutrizione'  },
    check:       { icon: 'ph-chart-line', label: 'Check'       },
  };

  // months visible per viewport, by view mode
  const MONTHS_PER_VIEW = { anno: 12, semestre: 6, mese: 1 };
  const VIEW_INDEX      = { anno: 0, semestre: 1, mese: 2 };
  const AVG_DAYS_MONTH  = 30.4375;

  const PAD         = 60;   // left/right inner padding of the track (px)
  const DOT_GAP     = 18;   // min px between dots before nudging
  const CARD_W      = 220;  // expanded card width
  const PHASE_MIN_W = 26;   // minimum visible width of a phase band (px)
  const PHASE_H     = 132;  // height of a phase band, centred on the axis

  window.percorsoTimeline = function (opts) {
    return {
      /* ── reactive state ── */
      apiUrl:       opts.apiUrl || '',
      phaseUrl:     opts.phaseUrl || '',          // base URL for phase create/delete
      canManage:    !!opts.canManage,             // professional can add/remove phases
      filters:      ['allenamento', 'nutrizione', 'check', 'fase'],
      view:         'anno',
      openId:       null,
      openPhaseId:  null,
      events:       [],
      phases:       [],
      placedEvents: [],
      placedPhases: [],
      months:       [],
      windowStart:  '',
      windowEnd:    '',
      loading:      false,
      saving:       false,
      trackWidth:   800,
      trackHeight:  198,
      axisY:        92,
      popPos:       { left: 0, bottom: 0 },   // viewport coords for the teleported popover

      /* ── add-phase form ── */
      formOpen:  false,
      formError: '',
      form:      { title: '', note: '', start_date: '', duration_value: 8, duration_unit: 'WEEKS' },

      /* ── internal (not reactive) ── */
      _dragging:   false,
      _startX:     0,
      _scrollLeft: 0,
      _moved:      false,

      /* ── lifecycle ── */
      init() {
        this._computeHeight();
        this.fetchEvents();
        this.$nextTick(() => this._initDragScroll());
        // close the open card / phase / form on Esc
        this._onKey = (e) => {
          if (e.key !== 'Escape') return;
          if (this.formOpen) { this.closeForm(); return; }
          this.openId = null;
          this.openPhaseId = null;
        };
        window.addEventListener('keydown', this._onKey);
        // recompute scale on resize (viewport-relative); a moved viewport
        // invalidates the popover's fixed coords, so close it.
        this._onResize = () => { this.openId = null; this.openPhaseId = null; this._layout(); };
        window.addEventListener('resize', this._onResize);
        // the popover is teleported to <body> with fixed coords anchored to a
        // dot — page scroll detaches it from its anchor, so close it.
        this._onWinScroll = () => {
          if (this.openId || this.openPhaseId) { this.openId = null; this.openPhaseId = null; }
        };
        window.addEventListener('scroll', this._onWinScroll, { passive: true });
      },

      /* ── API ── */
      async fetchEvents() {
        if (this.loading) return;
        this.loading = true;
        try {
          const url = new URL(this.apiUrl, window.location.origin);
          const r = await fetch(url.toString(), { credentials: 'same-origin' });
          if (!r.ok) throw new Error('HTTP ' + r.status);
          const d = await r.json();
          this.events      = d.events || [];
          this.phases      = d.phases || [];
          this.windowStart = d.window_start || '';
          this.windowEnd   = d.window_end   || '';
          this._layout();
        } catch (err) {
          console.warn('[percorsoTimeline] fetch error:', err);
        } finally {
          this.loading = false;
          // the scroll container is display:none while loading, so the layout
          // above measured a 0/fallback width. Recompute now that it's visible
          // so the track fills the full container width, then start at the left.
          this.$nextTick(() => {
            this._layout();
            const el = this.$refs.scrollContainer;
            if (el) el.scrollLeft = 0;
          });
        }
      },

      /* ── view mode (interval) ── */
      setView(mode) {
        if (mode === this.view || !MONTHS_PER_VIEW[mode]) return;
        this.view = mode;
        this.openId = null;
        this._layout();
        this.$nextTick(() => {
          const el = this.$refs.scrollContainer;
          if (el) el.scrollLeft = 0;   // show the first slice
        });
      },
      viewActive(mode) { return this.view === mode; },
      viewIndex() { return VIEW_INDEX[this.view] || 0; },

      /* ── filters ── */
      toggleFilter(type) {
        const i = this.filters.indexOf(type);
        if (i === -1) {
          this.filters.push(type);
        } else {
          if (this.filters.length === 1) return;
          this.filters.splice(i, 1);
        }
        this.openId = null;
        this._layout();
      },
      filterActive(type) { return this.filters.includes(type); },

      /* ── open / close events ── */
      toggle(ev) {
        if (this._moved) return;            // ignore clicks that were drags
        this.openPhaseId = null;
        this.openId = this.openId === ev.id ? null : ev.id;
        if (this.openId) this.$nextTick(() => this._setPopPos(ev.x, 16));
      },
      isOpen(ev)  { return this.openId === ev.id; },
      openEvent() { return this.placedEvents.find(e => e.id === this.openId) || null; },

      /* ── open / close phases ── */
      togglePhase(ph) {
        if (this._moved) return;
        this.openId = null;
        this.openPhaseId = this.openPhaseId === ph.id ? null : ph.id;
        if (this.openPhaseId) this.$nextTick(() => this._setPopPos(ph.x + ph.w / 2, this.phaseHeight() / 2 + 10));
      },

      /* position the body-teleported popover above its anchor, in viewport
         coords, clamped horizontally to the window */
      _setPopPos(anchorX, aboveOffset) {
        const el = this.$refs.scrollContainer;
        if (!el) return;
        const rect = el.getBoundingClientRect();
        const screenX = rect.left + (anchorX - el.scrollLeft);
        let left = screenX - CARD_W / 2;
        left = Math.max(8, Math.min(left, window.innerWidth - 8 - CARD_W));
        const bottom = window.innerHeight - (rect.top + this.axisY - aboveOffset);
        this.popPos = { left: Math.round(left), bottom: Math.round(bottom) };
      },
      isPhaseOpen(ph) { return this.openPhaseId === ph.id; },
      openPhase()     { return this.placedPhases.find(p => p.id === this.openPhaseId) || null; },

      /* ── layout ── */
      _layout() {
        if (!this.windowStart || !this.windowEnd) {
          this.placedEvents = [];
          this.months = [];
          return;
        }

        const el = this.$refs.scrollContainer;
        const viewportW = (el && el.clientWidth) ? el.clientWidth : 1000;

        this._computeHeight();

        const wStart = new Date(this.windowStart);
        let   wEnd   = new Date(this.windowEnd);
        // The scroll horizon always reaches one year past the latest activity.
        // A phase added live (or its end date) pushes the horizon out right
        // away, without waiting for a reload.
        const plusYear = (iso) => { const d = new Date(iso); d.setFullYear(d.getFullYear() + 1); return d; };
        this.phases.forEach((p) => { const e = plusYear(p.end); if (e > wEnd) wEnd = e; });
        const totalDays = Math.max(1, (wEnd - wStart) / 86400000);

        // px/day so that MONTHS_PER_VIEW months exactly fill the viewport.
        // Floor it so the data span always fills at least the usable width —
        // otherwise a span shorter than the view (e.g. < 12 months in "anno")
        // leaves the track padded with empty space instead of filling it.
        const monthsPerView = MONTHS_PER_VIEW[this.view] || 12;
        const usable   = Math.max(320, viewportW - PAD * 2);
        const pxPerDay = Math.max(usable / (monthsPerView * AVG_DAYS_MONTH), usable / totalDays);

        this.trackWidth = Math.max(viewportW, Math.round(totalDays * pxPerDay) + PAD * 2);
        this.months = this._buildMonths(wStart, wEnd, pxPerDay);

        const filtered = this.events.filter(e => this.filters.includes(e.type));

        // place dots on the axis; nudge overlapping ones just enough to stay tappable
        let lastX = -Infinity;
        const placed = filtered.map((ev) => {
          const evDate = new Date(ev.date);
          const dayOff = Math.max(0, (evDate - wStart) / 86400000);
          let x = Math.round(dayOff * pxPerDay) + PAD;
          if (x - lastX < DOT_GAP) x = lastX + DOT_GAP;
          lastX = x;
          return { ...ev, x, meta: TYPE_META[ev.type] || TYPE_META.check };
        });

        // if the currently open event got filtered out, close it
        if (this.openId != null && !placed.some(e => e.id === this.openId)) {
          this.openId = null;
        }
        this.placedEvents = placed;

        // place phase bands (translucent period blocks sitting across the axis)
        const showPhases = this.filters.includes('fase');
        const placedPhases = !showPhases ? [] : this.phases.map((ph) => {
          const sDate = new Date(ph.start);
          const eDate = new Date(ph.end);
          const sOff  = Math.max(0, (sDate - wStart) / 86400000);
          const eOff  = Math.max(sOff, (eDate - wStart) / 86400000);
          const x     = Math.round(sOff * pxPerDay) + PAD;
          const w     = Math.max(PHASE_MIN_W, Math.round((eOff - sOff) * pxPerDay));
          return { ...ph, x, w };
        });
        if (this.openPhaseId != null && !placedPhases.some(p => p.id === this.openPhaseId)) {
          this.openPhaseId = null;
        }
        this.placedPhases = placedPhases;
      },

      _buildMonths(start, end, pxPerDay) {
        const months = [];
        const cur = new Date(start.getFullYear(), start.getMonth(), 1);
        while (cur <= end) {
          const dayOff = (cur - start) / 86400000;
          const isJan  = cur.getMonth() === 0;
          months.push({
            label: MONTH_NAMES_IT[cur.getMonth()] + ' ' + cur.getFullYear(),
            isJan,
            x: Math.round(dayOff * pxPerDay) + PAD,
          });
          cur.setMonth(cur.getMonth() + 1);
        }
        return months;
      },

      formatDate(iso) {
        if (!iso) return '';
        const d = new Date(iso);
        return d.getDate() + ' ' + MONTH_NAMES_IT[d.getMonth()] + ' ' + d.getFullYear();
      },

      phaseTop()  { return this.axisY - this.phaseHeight() / 2; },
      phaseHeight() { return PHASE_H; },

      /* track height is content-driven (not viewport-driven), so the container
         hugs the timeline exactly — no dead band of page background below it.
         room above the axis clears the phase flag + dots; room below clears the
         phase band + month labels. */
      _computeHeight() {
        const phaseH = this.phaseHeight();
        const labelRoom = 40;                              // month labels below the axis
        this.axisY = Math.round(phaseH / 2 + 26);          // clearance above
        this.trackHeight = this.axisY + Math.round(phaseH / 2) + labelRoom;
      },
      durationLabel(ph) {
        const u = ph.duration_unit === 'MONTHS'
          ? (ph.duration_value === 1 ? 'mese' : 'mesi')
          : (ph.duration_value === 1 ? 'settimana' : 'settimane');
        return ph.duration_value + ' ' + u;
      },
      phaseRange(ph) {
        return this.formatDate(ph.start) + ' → ' + this.formatDate(ph.end);
      },

      /* ── add-phase form ── */
      openForm() {
        this.openId = null;
        this.openPhaseId = null;
        this.formError = '';
        this.form = {
          title: '', note: '',
          start_date: new Date().toISOString().slice(0, 10),
          duration_value: 8, duration_unit: 'WEEKS',
        };
        this.formOpen = true;
      },
      closeForm() { this.formOpen = false; },

      _csrf() {
        return document.querySelector('[name=csrfmiddlewaretoken]')?.value
          || (document.cookie.split('; ').find(r => r.startsWith('csrftoken=')) || '').split('=')[1]
          || '';
      },

      async submitPhase() {
        if (this.saving) return;
        this.formError = '';
        if (!this.form.title.trim())     { this.formError = 'Inserisci un titolo.'; return; }
        if (!this.form.start_date)       { this.formError = "Scegli la data d'inizio."; return; }
        if (!(this.form.duration_value >= 1)) { this.formError = 'La durata deve essere almeno 1.'; return; }

        this.saving = true;
        try {
          const r = await fetch(this.phaseUrl, {
            method: 'POST', credentials: 'same-origin',
            headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this._csrf() },
            body: JSON.stringify({
              title: this.form.title.trim(),
              note: this.form.note.trim(),
              start_date: this.form.start_date,
              duration_value: this.form.duration_value,
              duration_unit: this.form.duration_unit,
            }),
          });
          const d = await r.json();
          if (!r.ok) { this.formError = d.error || 'Errore durante il salvataggio.'; return; }
          this.phases.push(d);
          this.formOpen = false;
          this._layout();
          this.$nextTick(() => {
            this.openPhaseId = d.id;
            const ph = this.openPhase();
            if (ph) this._setPopPos(ph.x + ph.w / 2, this.phaseHeight() / 2 + 10);
          });
        } catch (err) {
          this.formError = 'Errore di rete. Riprova.';
        } finally {
          this.saving = false;
        }
      },

      async deletePhase(ph) {
        if (this.saving) return;
        this.saving = true;
        try {
          const r = await fetch(this.phaseUrl + ph.id + '/', {
            method: 'DELETE', credentials: 'same-origin',
            headers: { 'X-CSRFToken': this._csrf() },
          });
          if (!r.ok) return;
          this.phases = this.phases.filter(p => p.id !== ph.id);
          this.openPhaseId = null;
          this._layout();
        } finally {
          this.saving = false;
        }
      },

      /* ── drag-scroll (horizontal only) ── */
      _initDragScroll() {
        const el = this.$refs.scrollContainer;
        if (!el) return;

        const onDown = (e) => {
          this._dragging   = true;
          this._moved      = false;
          this._startX     = e.pageX - el.offsetLeft;
          this._scrollLeft = el.scrollLeft;
          el.style.cursor  = 'grabbing';
        };
        const onUp = () => {
          this._dragging  = false;
          el.style.cursor = 'grab';
          // let the click handler read _moved, then reset shortly after
          setTimeout(() => { this._moved = false; }, 0);
        };
        const onMove = (e) => {
          if (!this._dragging) return;
          e.preventDefault();
          const dx = (e.pageX - el.offsetLeft) - this._startX;
          if (Math.abs(dx) > 4) this._moved = true;
          el.scrollLeft = this._scrollLeft - dx * 1.4;
        };

        // any horizontal scroll detaches the popover from its dot — close it
        el.addEventListener('scroll', () => {
          if (this.openId || this.openPhaseId) { this.openId = null; this.openPhaseId = null; }
        }, { passive: true });

        el.addEventListener('mousedown',  onDown);
        el.addEventListener('mouseup',    onUp);
        el.addEventListener('mouseleave', onUp);
        el.addEventListener('mousemove',  onMove);

        // touch
        let tx = 0, ts = 0;
        el.addEventListener('touchstart', e => { tx = e.touches[0].pageX; ts = el.scrollLeft; }, { passive: true });
        el.addEventListener('touchmove',  e => { el.scrollLeft = ts - (e.touches[0].pageX - tx); }, { passive: true });
      },
    };
  };

})();
