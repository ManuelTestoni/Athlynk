/* Percorso Timeline — Alpine.js component
 * Horizontal infographic timeline with drag-scroll, filters, and pagination.
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

  const PX_PER_DAY   = 14;   // horizontal density
  const COLLISION_GAP = 180; // min px gap before switching sides
  const VERT_STEP    = 52;   // px added when both sides collide
  const CARD_H       = 96;   // estimated card height for geometry

  window.percorsoTimeline = function (opts) {
    return {
      /* ── reactive state ── */
      apiUrl:           opts.apiUrl || '',
      filters:          ['allenamento', 'nutrizione', 'check'],
      events:           [],
      placedEvents:     [],
      months:           [],
      windowStart:      '',
      windowEnd:        '',
      relationshipStart:'',
      hasMore:          false,
      loading:          false,
      loadingMore:      false,
      trackWidth:       800,
      trackHeight:      380,
      axisY:            190,

      /* ── internal (not reactive) ── */
      _dragging:   false,
      _startX:     0,
      _scrollLeft: 0,

      /* ── lifecycle ── */
      init() {
        this.axisY = Math.round(this.trackHeight / 2);
        this.fetchEvents(null);
        this.$nextTick(() => this._initDragScroll());
      },

      /* ── API ── */
      async fetchEvents(before) {
        if (this.loading || this.loadingMore) return;
        if (before) { this.loadingMore = true; } else { this.loading = true; }

        try {
          const url = new URL(this.apiUrl, window.location.origin);
          if (before) url.searchParams.set('before', before);

          const r = await fetch(url.toString(), { credentials: 'same-origin' });
          if (!r.ok) throw new Error('HTTP ' + r.status);
          const d = await r.json();

          if (before) {
            const seen = new Set(this.events.map(e => e.id));
            const older = d.events.filter(e => !seen.has(e.id));
            this.events = [...older, ...this.events];
            // extend the known window backwards
            if (d.window_start) this.windowStart = d.window_start;
          } else {
            this.events           = d.events || [];
            this.windowStart      = d.window_start || '';
            this.windowEnd        = d.window_end   || '';
            this.relationshipStart= d.relationship_start || '';
          }

          this.hasMore = !!d.has_more;

          this._layout();

          // after layout: scroll right so most-recent events are visible
          if (!before) {
            this.$nextTick(() => {
              const el = this.$refs.scrollContainer;
              if (el) el.scrollLeft = el.scrollWidth;
            });
          }
        } catch (err) {
          console.warn('[percorsoTimeline] fetch error:', err);
        } finally {
          this.loading     = false;
          this.loadingMore = false;
        }
      },

      loadMore() {
        if (this.hasMore && !this.loadingMore) this.fetchEvents(this.windowStart);
      },

      /* ── filters ── */
      toggleFilter(type) {
        const i = this.filters.indexOf(type);
        if (i === -1) {
          this.filters.push(type);
        } else {
          if (this.filters.length === 1) return;
          this.filters.splice(i, 1);
        }
        this._layout();
      },

      filterActive(type) { return this.filters.includes(type); },

      /* ── layout ── */
      _layout() {
        if (!this.windowStart || !this.windowEnd) {
          this.placedEvents = [];
          this.months = [];
          return;
        }

        const wStart   = new Date(this.windowStart);
        const wEnd     = new Date(this.windowEnd);
        const totalDays = Math.max(1, (wEnd - wStart) / 86400000);

        this.trackWidth = Math.max(860, Math.round(totalDays * PX_PER_DAY) + 120);
        this.months     = this._buildMonths(wStart, wEnd);

        const filtered = this.events.filter(e => this.filters.includes(e.type));

        const occupiedAbove = [];
        const occupiedBelow = [];
        const placed = [];

        filtered.forEach((ev, idx) => {
          const evDate   = new Date(ev.date);
          const dayOff   = Math.max(0, (evDate - wStart) / 86400000);
          const x        = Math.round(dayOff * PX_PER_DAY) + 60;

          let side    = idx % 2 === 0 ? 'above' : 'below';
          let vOffset = 0;

          const aboveHit = this._collides(occupiedAbove, x);
          const belowHit = this._collides(occupiedBelow, x);

          if (side === 'above' && aboveHit && !belowHit)       side = 'below';
          else if (side === 'below' && belowHit && !aboveHit)  side = 'above';
          else if (aboveHit && belowHit)                       vOffset = VERT_STEP;

          (side === 'above' ? occupiedAbove : occupiedBelow).push({ x, xEnd: x + 160 });

          placed.push({
            ...ev,
            x,
            side,
            vOffset,
            meta: TYPE_META[ev.type] || TYPE_META.check,
          });
        });

        this.placedEvents = placed;
      },

      _collides(list, x) {
        return list.some(o => x < o.xEnd + COLLISION_GAP && x + 160 > o.x - COLLISION_GAP);
      },

      _buildMonths(start, end) {
        const months = [];
        const cur = new Date(start.getFullYear(), start.getMonth(), 1);
        while (cur <= end) {
          const dayOff = (cur - start) / 86400000;
          months.push({
            label: MONTH_NAMES_IT[cur.getMonth()] + ' ' + cur.getFullYear(),
            fullLabel: MONTH_NAMES_FULL[cur.getMonth()] + ' ' + cur.getFullYear(),
            x: Math.round(dayOff * PX_PER_DAY) + 60,
          });
          cur.setMonth(cur.getMonth() + 1);
        }
        return months;
      },

      /* ── geometry helpers used in template ── */
      connectorStyle(ev) {
        const gap = 28 + ev.vOffset;
        const top = ev.side === 'above' ? this.axisY - gap : this.axisY;
        return [
          'position:absolute',
          `left:${ev.x}px`,
          `top:${top}px`,
          'width:1px',
          `height:${gap}px`,
          'background:repeating-linear-gradient(to bottom,var(--al-rule-strong) 0,var(--al-rule-strong) 4px,transparent 4px,transparent 7px)',
          'pointer-events:none',
          'z-index:2',
        ].join(';');
      },

      cardTop(ev) {
        return ev.side === 'above'
          ? this.axisY - CARD_H - 28 - ev.vOffset
          : this.axisY + 28 + ev.vOffset;
      },

      formatDate(iso) {
        if (!iso) return '';
        const d = new Date(iso);
        return d.getDate() + ' ' + MONTH_NAMES_IT[d.getMonth()];
      },

      /* ── drag-scroll ── */
      _initDragScroll() {
        const el = this.$refs.scrollContainer;
        if (!el) return;

        const onDown = (e) => {
          this._dragging   = true;
          this._startX     = e.pageX - el.offsetLeft;
          this._scrollLeft = el.scrollLeft;
          el.style.cursor  = 'grabbing';
        };
        const onUp = () => {
          this._dragging  = false;
          el.style.cursor = 'grab';
        };
        const onMove = (e) => {
          if (!this._dragging) return;
          e.preventDefault();
          const dx = (e.pageX - el.offsetLeft) - this._startX;
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
