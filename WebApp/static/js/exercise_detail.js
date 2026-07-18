/**
 * Athlynk · Exercise Detail Drawer
 *
 * Read-only catalog detail (gif, description, muscles, instructions) for one
 * exercise — opened from a plan/scheda row, coach or athlete side alike.
 * Mirrors the exercise-trend drawer's global-handle pattern so any page can
 * call it without owning its own Alpine scope.
 *
 * Open with: `AthlynkExerciseDetail.open(exerciseId, name)`.
 * Data comes from `/api/exercises/<id>/` (coach- and client-session aware).
 */
(function () {
  document.addEventListener('alpine:init', () => {
    Alpine.data('exerciseDetail', () => ({
      isOpen: false,
      loading: false,
      error: false,
      exerciseName: '',
      ex: null,

      init() {
        window.__athlynkExerciseDetail = this;
        window.addEventListener('keydown', (e) => {
          if (e.key === 'Escape' && this.isOpen) this.close();
        });
      },

      open(exerciseId, name) {
        this.exerciseName = name || 'Esercizio';
        this.ex = null;
        this.error = false;
        this.loading = true;
        if (!this.isOpen) window.panelLock && window.panelLock.acquire();
        this.isOpen = true;

        fetch(`/api/exercises/${exerciseId}/`, { credentials: 'same-origin' })
          .then(r => r.ok ? r.json() : Promise.reject(r.status))
          .then(d => {
            this.ex = d;
            this.exerciseName = d.name || this.exerciseName;
            this.loading = false;
          })
          .catch(err => {
            console.error('[AthlynkExerciseDetail] load failed', err);
            this.loading = false;
            this.error = true;
          });
      },

      close() {
        if (this.isOpen) window.panelLock && window.panelLock.release();
        this.isOpen = false;
      },
    }));
  });

  function _get() {
    if (window.__athlynkExerciseDetail) return window.__athlynkExerciseDetail;
    if (typeof Alpine !== 'undefined') {
      const el = document.getElementById('athlynk-exercise-detail-root');
      if (el) { try { return Alpine.$data(el); } catch (_) { /* */ } }
    }
    return null;
  }

  window.AthlynkExerciseDetail = {
    open(exerciseId, name) {
      const d = _get();
      if (d) { d.open(exerciseId, name); return; }
      setTimeout(() => { const x = _get(); if (x) x.open(exerciseId, name); }, 50);
    },
    close() { const d = _get(); if (d) d.close(); },
  };
})();
