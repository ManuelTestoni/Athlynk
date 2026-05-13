/* Agenda v2 — custom Alpine.js calendar
   Italian locale, three views (today/week/month), works against
   /api/agenda/events/ (GET) and POST for create. */

const APPOINTMENT_TYPES = [
  { value: 'check',        label: 'Check progressi', color: '#4f4ff0', icon: 'ph ph-clipboard-text' },
  { value: 'prima_visita', label: 'Prima visita',    color: '#0ea271', icon: 'ph ph-first-aid-kit' },
  { value: 'visita',       label: 'Visita',          color: '#2563eb', icon: 'ph ph-stethoscope' },
  { value: 'consulenza',   label: 'Consulenza',      color: '#d97706', icon: 'ph ph-video-camera' },
];

const IT_DOW = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
const IT_DOW_FULL = ['Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica'];

function ymd(d) {
  return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
}
function startOfDay(d) { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; }
function endOfDay(d)   { const x = new Date(d); x.setHours(23, 59, 59, 999); return x; }
function addDays(d, n) { const x = new Date(d); x.setDate(x.getDate() + n); return x; }
function isoWeekStart(d) {
  // Monday = first day
  const x = startOfDay(d);
  const day = (x.getDay() + 6) % 7; // 0=Mon..6=Sun
  x.setDate(x.getDate() - day);
  return x;
}
function sameDay(a, b) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}
function fmtTime(d) {
  return new Intl.DateTimeFormat('it-IT', { hour: '2-digit', minute: '2-digit' }).format(d);
}
function fmtMonthYear(d) {
  return new Intl.DateTimeFormat('it-IT', { month: 'long', year: 'numeric' }).format(d);
}
function fmtFullDate(d) {
  return new Intl.DateTimeFormat('it-IT', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).format(d);
}
function fmtDayLabel(d) {
  return new Intl.DateTimeFormat('it-IT', { weekday: 'long', day: 'numeric', month: 'long' }).format(d);
}

function emptyAgendaEvent() {
  return {
    title: '',
    client_id: null,
    appointment_type: 'check',
    start_datetime: '',
    end_datetime: '',
    description: '',
    meeting_url: '',
    is_recurring: false,
    recurrence_rule: 'settimanale',
  };
}

document.addEventListener('alpine:init', () => {
  Alpine.data('agendaApp', () => ({
    view: 'today',
    currentDate: new Date(),
    miniCursor: new Date(),
    events: [],
    loading: false,
    selectedDate: new Date(),

    canManage: window.AGENDA_CAN_MANAGE === true,
    typeFilter: APPOINTMENT_TYPES.map(t => t.value), // all enabled
    types: APPOINTMENT_TYPES,
    dowLabels: IT_DOW,

    // modals
    showDetailModal: false,
    selectedEvent: null,
    showCreateModal: false,
    newEvent: emptyAgendaEvent(),
    clientSearchQuery: '',
    clientSearchResults: [],
    selectedClientName: '',

    _emptyEvent() {
      return emptyAgendaEvent();
    },

    async init() {
      await this.fetchEvents();
    },

    async fetchEvents() {
      this.loading = true;
      try {
        const r = await fetch('/api/agenda/events/');
        if (r.ok) {
          const data = await r.json();
          this.events = (Array.isArray(data) ? data : []).map(e => ({
            ...e,
            _start: new Date(e.start),
            _end: new Date(e.end),
            _type: (e.type || '').toLowerCase(),
          }));
        }
      } catch (e) {
        console.error(e);
      } finally {
        this.loading = false;
      }
    },

    filteredEvents() {
      return this.events.filter(e => this.typeFilter.includes(e._type));
    },

    eventsOn(d) {
      const day = startOfDay(d).getTime();
      return this.filteredEvents()
        .filter(e => sameDay(e._start, d))
        .sort((a, b) => a._start - b._start);
    },

    hasEventsOn(d) {
      return this.filteredEvents().some(e => sameDay(e._start, d));
    },

    typeLabel(t) {
      const m = APPOINTMENT_TYPES.find(x => x.value === t);
      return m ? m.label : t;
    },
    typeColor(t) {
      const m = APPOINTMENT_TYPES.find(x => x.value === t);
      return m ? m.color : '#1c4a52';
    },
    typeClass(t) {
      const known = APPOINTMENT_TYPES.find(x => x.value === t);
      return known ? `event-${t}` : 'event-default';
    },

    toggleType(t) {
      const i = this.typeFilter.indexOf(t);
      if (i >= 0) this.typeFilter.splice(i, 1);
      else this.typeFilter.push(t);
    },

    /* ---------------- navigation ---------------- */
    goToday() { this.currentDate = new Date(); this.miniCursor = new Date(); },
    prev() {
      if (this.view === 'today') this.currentDate = addDays(this.currentDate, -1);
      else if (this.view === 'week') this.currentDate = addDays(this.currentDate, -7);
      else this.currentDate = new Date(this.currentDate.getFullYear(), this.currentDate.getMonth() - 1, 1);
    },
    next() {
      if (this.view === 'today') this.currentDate = addDays(this.currentDate, 1);
      else if (this.view === 'week') this.currentDate = addDays(this.currentDate, 7);
      else this.currentDate = new Date(this.currentDate.getFullYear(), this.currentDate.getMonth() + 1, 1);
    },
    setView(v) {
      this.view = v;
    },
    headerTitle() {
      if (this.view === 'today') return fmtFullDate(this.currentDate);
      if (this.view === 'week') {
        const start = isoWeekStart(this.currentDate);
        const end = addDays(start, 6);
        const sameMonth = start.getMonth() === end.getMonth();
        const fmtA = new Intl.DateTimeFormat('it-IT', { day: 'numeric', month: sameMonth ? undefined : 'short' });
        const fmtB = new Intl.DateTimeFormat('it-IT', { day: 'numeric', month: 'short', year: 'numeric' });
        return `${fmtA.format(start)} – ${fmtB.format(end)}`;
      }
      return fmtMonthYear(this.currentDate);
    },

    /* ---------------- today view ---------------- */
    todayEvents() {
      return this.eventsOn(this.currentDate);
    },
    upcomingDays() {
      // next 7 days starting tomorrow, grouped
      const groups = [];
      for (let i = 1; i <= 7; i++) {
        const d = addDays(this.currentDate, i);
        const events = this.eventsOn(d);
        if (events.length) groups.push({ date: d, events });
      }
      return groups;
    },

    /* ---------------- week view ---------------- */
    weekDays() {
      const start = isoWeekStart(this.currentDate);
      return Array.from({ length: 7 }, (_, i) => addDays(start, i));
    },
    weekHours() {
      const hours = [];
      for (let h = 7; h <= 21; h++) hours.push(h);
      return hours;
    },
    weekEventStyle(e) {
      // pixel height per hour = 44 (matches CSS .agenda-week-cell height)
      const HOUR = 44;
      const dayStart = startOfDay(e._start);
      const top = ((e._start - dayStart) / 3600000 - 7) * HOUR; // 7 = first hour
      const dur = Math.max(0.5, (e._end - e._start) / 3600000);
      const height = dur * HOUR - 2;
      return `top: ${top}px; height: ${height}px;`;
    },
    weekEventsForDay(d) {
      return this.eventsOn(d).filter(e => e._start.getHours() >= 7 && e._start.getHours() <= 21);
    },

    /* ---------------- month view ---------------- */
    monthGrid() {
      const first = new Date(this.currentDate.getFullYear(), this.currentDate.getMonth(), 1);
      const startOffset = (first.getDay() + 6) % 7;
      const gridStart = addDays(first, -startOffset);
      const cells = [];
      for (let i = 0; i < 42; i++) {
        const d = addDays(gridStart, i);
        cells.push({
          date: d,
          isOut: d.getMonth() !== this.currentDate.getMonth(),
          isToday: sameDay(d, new Date()),
          events: this.eventsOn(d),
        });
      }
      return cells;
    },

    /* ---------------- mini calendar ---------------- */
    miniGrid() {
      const first = new Date(this.miniCursor.getFullYear(), this.miniCursor.getMonth(), 1);
      const startOffset = (first.getDay() + 6) % 7;
      const gridStart = addDays(first, -startOffset);
      return Array.from({ length: 42 }, (_, i) => {
        const d = addDays(gridStart, i);
        return {
          date: d,
          isOut: d.getMonth() !== this.miniCursor.getMonth(),
          isToday: sameDay(d, new Date()),
          isSelected: sameDay(d, this.currentDate),
          hasEvents: this.hasEventsOn(d),
        };
      });
    },
    miniPrev() { this.miniCursor = new Date(this.miniCursor.getFullYear(), this.miniCursor.getMonth() - 1, 1); },
    miniNext() { this.miniCursor = new Date(this.miniCursor.getFullYear(), this.miniCursor.getMonth() + 1, 1); },
    miniSelect(d) {
      this.currentDate = d;
      if (this.view === 'month') this.view = 'today';
    },

    /* ---------------- detail / create ---------------- */
    openDetail(evt) {
      this.selectedEvent = evt;
      this.showDetailModal = true;
    },
    closeDetail() { this.showDetailModal = false; this.selectedEvent = null; },

    openCreate(dateObj) {
      if (!this.canManage) return;
      const d = dateObj || this.currentDate;
      const start = new Date(d);
      if (start.getHours() === 0) start.setHours(9, 0, 0, 0);
      const end = new Date(start);
      end.setHours(end.getHours() + 1);
      this.newEvent = this._emptyEvent();
      this.newEvent.start_datetime = this._toLocalInput(start);
      this.newEvent.end_datetime = this._toLocalInput(end);
      this.clientSearchQuery = '';
      this.clientSearchResults = [];
      this.selectedClientName = '';
      this.showCreateModal = true;
    },
    closeCreate() { this.showCreateModal = false; },

    _toLocalInput(d) {
      const tzOffset = d.getTimezoneOffset();
      const local = new Date(d.getTime() - tzOffset * 60000);
      return local.toISOString().slice(0, 16);
    },

    async searchClients() {
      const q = this.clientSearchQuery.trim();
      if (q.length < 2) { this.clientSearchResults = []; return; }
      try {
        const r = await fetch('/api/clients/search/?q=' + encodeURIComponent(q));
        if (r.ok) this.clientSearchResults = await r.json();
      } catch (e) { this.clientSearchResults = []; }
    },

    selectClient(c) {
      this.newEvent.client_id = c.id;
      this.selectedClientName = c.name;
      this.clientSearchResults = [];
      this.clientSearchQuery = '';
    },

    typePlaceholder() {
      const map = {
        check: 'Es. Check mensile',
        prima_visita: 'Es. Prima visita',
        visita: 'Es. Visita di controllo',
        consulenza: 'Es. Videoconsulenza',
      };
      return map[this.newEvent.appointment_type] || 'Titolo appuntamento';
    },

    _csrf() {
      return document.querySelector('[name=csrfmiddlewaretoken]')?.value
        || (document.cookie.split('; ').find(r => r.startsWith('csrftoken=')) || '').split('=')[1]
        || '';
    },

    async saveAppointment() {
      const e = this.newEvent;
      if (!e.title || !e.client_id || !e.start_datetime || !e.end_datetime) {
        alert('Completa titolo, cliente, inizio e fine.');
        return;
      }
      try {
        const r = await fetch('/api/agenda/events/', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': this._csrf() },
          body: JSON.stringify(e),
        });
        if (r.ok) {
          this.showCreateModal = false;
          await this.fetchEvents();
        } else {
          const d = await r.json();
          alert(d.error || 'Errore di salvataggio');
        }
      } catch (err) { alert('Errore di rete'); }
    },

    /* ---------------- formatting helpers (exposed to template) ---------------- */
    fmtTime(d)      { return d ? fmtTime(d instanceof Date ? d : new Date(d)) : ''; },
    fmtFullDate(d)  { return d ? fmtFullDate(d instanceof Date ? d : new Date(d)) : ''; },
    fmtDayLabel(d)  { return d ? fmtDayLabel(d instanceof Date ? d : new Date(d)) : ''; },
    fmtDayNum(d)    { return d ? String(d.getDate()) : ''; },
    isToday(d)      { return d ? sameDay(d, new Date()) : false; },
  }));
});
