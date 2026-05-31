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

  const PAD       = 60;   // left/right inner padding of the track (px)
  const DOT_GAP   = 18;   // min px between dots before nudging
  const CARD_W    = 220;  // expanded card width

  window.percorsoTimeline = function (opts) {
    return {
      /* ── reactive state ── */
      apiUrl:       opts.apiUrl || '',
      filters:      ['allenamento', 'nutrizione', 'check'],
      view:         'anno',
      openId:       null,
      events:       [],
      placedEvents: [],
      months:       [],
      windowStart:  '',
      windowEnd:    '',
      loading:      false,
      trackWidth:   800,
      trackHeight:  320,
      axisY:        160,

      /* ── internal (not reactive) ── */
      _dragging:   false,
      _startX:     0,
      _scrollLeft: 0,
      _moved:      false,

      /* ── lifecycle ── */
      init() {
        this.axisY = Math.round(this.trackHeight / 2);
        this.fetchEvents();
        this.$nextTick(() => this._initDragScroll());
        // close the open card on Esc
        this._onKey = (e) => { if (e.key === 'Escape') this.openId = null; };
        window.addEventListener('keydown', this._onKey);
        // recompute scale on resize (viewport-relative)
        this._onResize = () => this._layout();
        window.addEventListener('resize', this._onResize);
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
          this.windowStart = d.window_start || '';
          this.windowEnd   = d.window_end   || '';
          this._layout();
          // start at the beginning of the journey (left), per design
          this.$nextTick(() => {
            const el = this.$refs.scrollContainer;
            if (el) el.scrollLeft = 0;
          });
        } catch (err) {
          console.warn('[percorsoTimeline] fetch error:', err);
        } finally {
          this.loading = false;
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
        this.openId = this.openId === ev.id ? null : ev.id;
      },
      isOpen(ev)  { return this.openId === ev.id; },
      openEvent() { return this.placedEvents.find(e => e.id === this.openId) || null; },

      /* ── layout ── */
      _layout() {
        if (!this.windowStart || !this.windowEnd) {
          this.placedEvents = [];
          this.months = [];
          return;
        }

        const el = this.$refs.scrollContainer;
        const viewportW = (el && el.clientWidth) ? el.clientWidth : 1000;

        const wStart = new Date(this.windowStart);
        const wEnd   = new Date(this.windowEnd);
        const totalDays = Math.max(1, (wEnd - wStart) / 86400000);

        // px/day so that MONTHS_PER_VIEW months exactly fill the viewport
        const monthsPerView = MONTHS_PER_VIEW[this.view] || 12;
        const usable   = Math.max(320, viewportW - PAD * 2);
        const pxPerDay = usable / (monthsPerView * AVG_DAYS_MONTH);

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

      /* ── geometry helpers used in template ── */
      // expanded card sits above the axis, horizontally centered on its dot,
      // clamped so it never spills past the track edges
      cardLeft(ev) {
        const half = CARD_W / 2;
        let left = ev.x - half;
        if (left < 8) left = 8;
        if (left + CARD_W > this.trackWidth - 8) left = this.trackWidth - 8 - CARD_W;
        return left;
      },

      formatDate(iso) {
        if (!iso) return '';
        const d = new Date(iso);
        return d.getDate() + ' ' + MONTH_NAMES_IT[d.getMonth()] + ' ' + d.getFullYear();
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
