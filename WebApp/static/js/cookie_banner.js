/* Cookie consent banner — vanilla JS, GDPR / ePrivacy compliant.
 *
 *  - Reads cookie "cookie_consent" (JSON: { consent_id, version, prefs }).
 *  - Re-prompts when cookie missing or its `version` != window.CONSENT_VERSION.
 *  - Three equally-prominent buttons: Accept all, Reject all, Customise.
 *  - Customise modal exposes Necessary (locked on), Preferences, Analytics, Marketing.
 *  - Posts to /api/consent/ which records the consent server-side and sets the cookie.
 *  - Exposes window.cookieConsent.{open, has, snapshot, savePrefs}.
 *  - Activates <script type="text/plain" data-cookie-category="..."> tags whose
 *    category was granted. All DOM is built via createElement (no innerHTML) to
 *    avoid any sanitization risk.
 */
(function () {
  const COOKIE_NAME = 'cookie_consent';
  const CONSENT_VERSION = window.CONSENT_VERSION
    || (document.querySelector('meta[name="consent-version"]') || {}).content
    || 'unknown';
  const API_URL = '/api/consent/';
  const CSRF_TOKEN = (document.querySelector('meta[name="csrf-token"]') || {}).content || '';

  function readCookie() {
    const m = document.cookie.split('; ').find(c => c.startsWith(COOKIE_NAME + '='));
    if (!m) return null;
    try {
      return JSON.parse(decodeURIComponent(m.split('=').slice(1).join('=')));
    } catch (e) { return null; }
  }

  function needsPrompt() {
    // Server-computed signal wins: it knows both the cookie state AND whether
    // the logged-in user has a stored CookieConsentRecord for current version.
    if (window.COOKIE_CONSENT_NEEDED === true) return true;
    if (window.COOKIE_CONSENT_NEEDED === false) return false;
    // Fallback (anonymous, no meta): use cookie only.
    const c = readCookie();
    if (!c) return true;
    if (c.version !== CONSENT_VERSION) return true;
    return false;
  }

  function currentPrefs() {
    const c = readCookie();
    return (c && c.prefs) || { necessary: true, preferences: false, analytics: false, marketing: false };
  }

  function activateAllowedScripts() {
    const prefs = currentPrefs();
    document.querySelectorAll('script[type="text/plain"][data-cookie-category]').forEach(orig => {
      const cat = orig.getAttribute('data-cookie-category');
      if (!prefs[cat]) return;
      const s = document.createElement('script');
      for (const a of orig.attributes) {
        if (a.name === 'type' || a.name === 'data-cookie-category') continue;
        s.setAttribute(a.name, a.value);
      }
      s.textContent = orig.textContent;
      orig.parentNode.replaceChild(s, orig);
    });
  }

  async function postConsent(prefs) {
    const existing = readCookie();
    try {
      const r = await fetch(API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRFToken': CSRF_TOKEN },
        body: JSON.stringify({
          consent_id: existing && existing.consent_id ? existing.consent_id : null,
          preferences: !!prefs.preferences,
          analytics: !!prefs.analytics,
          marketing: !!prefs.marketing,
        }),
      });
      return r.ok;
    } catch (e) {
      return false;
    }
  }

  /* ---------- DOM helpers ---------- */
  function el(tag, attrs, ...children) {
    const e = document.createElement(tag);
    if (attrs) {
      for (const k in attrs) {
        if (k === 'class') e.className = attrs[k];
        else if (k === 'text') e.textContent = attrs[k];
        else if (k.startsWith('on') && typeof attrs[k] === 'function') e.addEventListener(k.slice(2), attrs[k]);
        else e.setAttribute(k, attrs[k]);
      }
    }
    for (const c of children) {
      if (c == null) continue;
      e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    }
    return e;
  }

  /* ---------- DOM rendering ---------- */
  let bannerEl, modalEl, modalBackEl;
  let modalPrefs = { preferences: false, analytics: false, marketing: false };

  function buildBanner() {
    const root = document.getElementById('cookie-banner-root') || document.body.appendChild(el('div', { id: 'cookie-banner-root' }));

    /* ---- banner ---- */
    const titleNode = el('h2', { text: 'Rispettiamo la tua privacy' });
    const paraNode = el('p', null,
      'In conformità al GDPR (Reg. UE 2016/679) e alla normativa ePrivacy / Provv. Garante 10/06/2021, usiamo cookie tecnici sempre attivi e — solo previo tuo consenso — cookie di preferenze, analytics e marketing. Puoi accettare tutto, rifiutare tutti i non necessari o personalizzare la scelta. Dettagli su finalità, terze parti, conservazione e diritti nella ',
      el('a', { href: '/cookie/', text: 'Cookie Policy' }),
      ' e nella ',
      el('a', { href: '/privacy/', text: 'Privacy Policy' }),
      '.'
    );
    const closeX = el('button', {
      type: 'button',
      class: 'cc-close-x',
      onclick: doReject,
      'aria-label': 'Chiudi mantenendo solo i cookie tecnici necessari',
      text: '×',
    });
    const actions = el('div', { class: 'cc-actions' },
      el('button', { type: 'button', class: 'cc-btn cc-btn-primary', onclick: doAccept, text: 'Accetta tutto' }),
      el('button', { type: 'button', class: 'cc-btn', onclick: doReject, text: 'Solo necessari' }),
      el('button', { type: 'button', class: 'cc-btn', onclick: openCustom, text: 'Personalizza' }),
    );
    const banner = el('div', { class: 'cc-banner', role: 'dialog', 'aria-live': 'polite', 'aria-label': 'Preferenze cookie' },
      closeX, titleNode, paraNode, actions);
    bannerEl = el('div', { class: 'cc-root', id: 'cc-banner' }, banner);
    root.appendChild(bannerEl);

    /* ---- modal ---- */
    modalBackEl = el('div', { class: 'cc-modal-back', id: 'cc-modal-back', onclick: closeCustom });
    root.appendChild(modalBackEl);

    const head = el('div', { class: 'cc-modal-head' },
      el('h3', { text: 'Personalizza i cookie' }),
      el('button', { type: 'button', class: 'cc-modal-close', onclick: closeCustom, text: '×', 'aria-label': 'Chiudi' }),
    );

    function catRow(title, desc, key, locked) {
      const toggle = el('div', {
        class: 'cc-toggle' + (locked ? ' is-locked' : ''),
        role: 'checkbox',
        tabindex: locked ? '-1' : '0',
        'aria-disabled': locked ? 'true' : 'false',
      });
      if (!locked) {
        const flip = () => { modalPrefs[key] = !modalPrefs[key]; syncToggles(); };
        toggle.addEventListener('click', flip);
        toggle.addEventListener('keydown', e => {
          if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); flip(); }
        });
        toggle.setAttribute('data-cc-cat', key);
      }
      return el('div', { class: 'cc-cat' },
        el('div', { class: 'cc-cat-row' },
          el('div', null, el('h4', { text: title }), el('p', { text: desc })),
          toggle,
        ),
      );
    }

    const body = el('div', { class: 'cc-modal-body' },
      catRow('Necessari', 'Sessione, CSRF, autenticazione e salvataggio preferenze cookie.', 'necessary', true),
      catRow('Preferenze', 'Memorizzano scelte UI (tema, lingua) per migliorare l\'esperienza.', 'preferences', false),
      catRow('Analytics', 'Statistiche aggregate sull\'uso del sito.', 'analytics', false),
      catRow('Marketing', 'Pubblicità personalizzata e remarketing.', 'marketing', false),
    );

    const foot = el('div', { class: 'cc-modal-foot' },
      el('button', { type: 'button', class: 'cc-btn', onclick: doReject, text: 'Rifiuta tutto' }),
      el('button', { type: 'button', class: 'cc-btn', onclick: doAccept, text: 'Accetta tutto' }),
      el('button', { type: 'button', class: 'cc-btn cc-btn-bronze', onclick: doSave, text: 'Salva scelte' }),
    );

    modalEl = el('div', { class: 'cc-modal', id: 'cc-modal' },
      el('div', { class: 'cc-modal-panel' }, head, body, foot),
    );
    root.appendChild(modalEl);
  }

  function syncToggles() {
    document.querySelectorAll('#cc-modal .cc-toggle[data-cc-cat]').forEach(t => {
      const k = t.getAttribute('data-cc-cat');
      t.classList.toggle('is-on', !!modalPrefs[k]);
      t.setAttribute('aria-checked', modalPrefs[k] ? 'true' : 'false');
    });
  }

  function show() { bannerEl.classList.add('is-open'); }
  function hide() { bannerEl.classList.remove('is-open'); }
  function openCustom() {
    if (!modalEl) buildBanner();
    modalPrefs = { ...currentPrefs() };
    delete modalPrefs.necessary;
    syncToggles();
    modalEl.classList.add('is-open');
    modalBackEl.classList.add('is-open');
  }
  function closeCustom() {
    if (modalEl) modalEl.classList.remove('is-open');
    if (modalBackEl) modalBackEl.classList.remove('is-open');
  }

  async function persist(prefs) {
    await postConsent(prefs);
    activateAllowedScripts();
    hide();
    closeCustom();
  }

  function doAccept() { return persist({ preferences: true, analytics: true, marketing: true }); }
  function doReject() { return persist({ preferences: false, analytics: false, marketing: false }); }
  function doSave()   { return persist(modalPrefs); }

  /* ---------- public API ---------- */
  window.cookieConsent = {
    open: openCustom,
    has: (cat) => {
      const c = readCookie();
      return !!(c && c.prefs && c.prefs[cat]);
    },
    snapshot: () => currentPrefs(),
    savePrefs: (prefs) => persist(prefs),
  };

  /* ---------- bootstrap ---------- */
  function boot() {
    buildBanner();
    activateAllowedScripts();
    if (needsPrompt()) show();
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
