/* Shared week strip (partials/_week_strip.html): 7 day-circles, Monday-first,
   dispatches a custom window event with the picked date so any host page can
   filter its own content without this component knowing about it. */
(function () {
  const IT_LABELS = ['L', 'M', 'M', 'G', 'V', 'S', 'D'];

  function ymd(d) {
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }
  function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
  }
  function addDays(d, n) { const x = new Date(d); x.setDate(x.getDate() + n); return x; }
  function isoWeekStart(d) {
    const x = new Date(d); x.setHours(0, 0, 0, 0);
    const day = (x.getDay() + 6) % 7; // 0=Mon..6=Sun
    x.setDate(x.getDate() - day);
    return x;
  }

  document.addEventListener('alpine:init', () => {
    Alpine.data('weekStrip', (eventName) => ({
      anchor: new Date(),
      selected: new Date(),
      days: [],

      init() {
        this.build();
      },
      build() {
        const start = isoWeekStart(this.anchor);
        const today = new Date();
        this.days = Array.from({ length: 7 }, (_, i) => {
          const d = addDays(start, i);
          return {
            iso: ymd(d),
            date: d,
            initial: IT_LABELS[i],
            label: IT_LABELS[i],
            isToday: sameDay(d, today),
            isSelected: sameDay(d, this.selected),
          };
        });
      },
      prevWeek() { this.anchor = addDays(this.anchor, -7); this.build(); },
      nextWeek() { this.anchor = addDays(this.anchor, 7); this.build(); },
      selectDay(d) {
        this.selected = d.date;
        this.build();
        window.dispatchEvent(new CustomEvent(eventName, { detail: { date: d.iso } }));
      },
    }));
  });
})();
