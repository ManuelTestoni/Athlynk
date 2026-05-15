/* Athlynk — global toast store.
   Usage:
     Alpine.store('toasts').push({ kind: 'success', msg: 'Salvato' });
     Alpine.store('toasts').push({ kind: 'danger',  msg: 'Errore', ttl: 8000 });
   The host renders in base.html via Alpine.
*/
(function () {
  const KIND_ICONS = {
    success: 'ph-fill ph-check-circle',
    warn:    'ph-fill ph-warning-circle',
    danger:  'ph-fill ph-warning-octagon',
    info:    'ph-fill ph-info',
  };

  document.addEventListener('alpine:init', () => {
    Alpine.store('toasts', {
      items: [],
      _seq: 0,
      push({ kind = 'info', msg = '', ttl = 5000 } = {}) {
        const id = ++this._seq;
        this.items.push({ id, kind, msg, icon: KIND_ICONS[kind] || KIND_ICONS.info });
        if (ttl > 0) setTimeout(() => this.dismiss(id), ttl);
        return id;
      },
      dismiss(id) {
        const i = this.items.findIndex(t => t.id === id);
        if (i !== -1) this.items.splice(i, 1);
      },
      clear() { this.items = []; },
    });
  });
})();
