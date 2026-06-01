/* Athlynk — dialogo conferma/alert globale, animato (stile dark).
   Usage (Promise-based):
     if (!await window.alConfirm({ title: 'Eliminare?', subtitle: 'Azione irreversibile.' })) return;
     await window.alAlert({ title: 'Errore', subtitle: 'Riprova più tardi.' });

   Opzioni: { title, subtitle, icon, variant, confirmLabel, cancelLabel }
     variant: 'danger' (default) | 'neutral'
     icon:    classe Phosphor, default per variante
   Lo store regge una sola istanza alla volta; l'host è renderizzato in base.html.
*/
(function () {
  const DEFAULT_ICON = { danger: 'ph-link-break', neutral: 'ph-question' };

  document.addEventListener('alpine:init', () => {
    Alpine.store('confirm', {
      open: false,
      opts: {},
      _resolve: null,
      show(opts = {}) {
        const variant = opts.variant === 'neutral' ? 'neutral' : 'danger';
        this.opts = {
          title: 'Confermi?',
          subtitle: '',
          variant,
          icon: opts.icon || DEFAULT_ICON[variant],
          confirmLabel: 'Conferma',
          cancelLabel: 'Annulla',
          mode: opts.mode === 'alert' ? 'alert' : 'confirm',
          ...opts,
        };
        this.open = true;
        if (window.panelLock) window.panelLock.acquire();
        return new Promise((res) => { this._resolve = res; });
      },
      _close(result) {
        if (!this.open) return;
        this.open = false;
        if (window.panelLock) window.panelLock.release();
        if (this._resolve) { this._resolve(result); this._resolve = null; }
      },
      confirm() { this._close(this.opts.mode === 'alert' ? undefined : true); },
      cancel()  { this._close(this.opts.mode === 'alert' ? undefined : false); },
    });
  });

  function show(opts) {
    if (!window.Alpine || !Alpine.store('confirm')) {
      // Fallback se Alpine non è pronto: dialogo nativo.
      const ok = window.confirm([opts && opts.title, opts && opts.subtitle].filter(Boolean).join('\n\n'));
      return Promise.resolve(opts && opts.mode === 'alert' ? undefined : ok);
    }
    return Alpine.store('confirm').show(opts);
  }

  window.alConfirm = (opts = {}) => show({ ...opts, mode: 'confirm' });
  window.alAlert   = (opts = {}) => show({ ...opts, mode: 'alert' });
})();
