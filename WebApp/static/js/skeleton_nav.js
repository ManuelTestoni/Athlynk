/* skeleton_nav.js — Athlynk
   Page-transition skeletons for the SSR app. On a full-page internal
   navigation the browser keeps the old page frozen until the next
   document arrives from the server (DB query + network latency). We
   intercept the click, and after a short grace period paint a skeleton
   shaped like the *destination* page into .al-page so the wait reads
   as "instant".

   The skeleton must mirror the structure of the page being loaded, not
   a generic placeholder — so each route family routes to its own
   archetype (dashboard, list, detail, form, builder, chat).

   SAFE BOUNDARY: no fetch, no form submit, no state. Never calls
   preventDefault — the real navigation always proceeds untouched.
   The injected skeleton is discarded when the new document commits. */
(function () {
  'use strict';

  var DELAY = 140;            // ms before the skeleton shows (skips fast loads)
  var timer = null;
  var shown = false;

  /* ---- variant routing ----------------------------------------------
     Order matters: most specific families first. Where the same URL
     renders a different page per role (coach vs client), the role is
     read from <body data-role>. */
  function variantFor(path) {
    var role = document.body.getAttribute('data-role') || '';

    // chat conversation — message bubbles + composer
    if (/^\/chat\/\d+/.test(path)) return 'chat';

    // agenda — mini-calendar sidebar + month canvas
    if (/^\/agenda\/?$/.test(path)) return 'calendar';

    // business analytics — KPI row + chart panels
    if (/^\/analisi\/?$/.test(path)) return 'analytics';

    // chart pages — filter toolbar + chart card grid
    if (/^\/check\/(andamento|comparatore)/.test(path) ||
        /\/progressi\/?$/.test(path) ||
        /\/volume\/?$/.test(path)) return 'charts';

    // settings hub — grid of preference panels
    if (/^\/impostazioni\/?$/.test(path)) return 'settings';

    // profile — main column + side rail
    if (/^\/profilo\/?$/.test(path) ||
        /^\/il-mio-coach\/?$/.test(path)) return 'profile';

    // il mio percorso — stat trio + timeline rows
    if (/^\/il-mio-percorso\/?$/.test(path)) return 'timeline';

    // settings subpages & simple stacked forms (before builder:
    // anamnesi/crea and piano abbonamento are forms)
    if (/^\/impostazioni\//.test(path) ||
        /\/(registra|modifica)(\/|$)/.test(path) ||
        /\/anamnesi\/crea/.test(path) ||
        /\/abbonamenti\/piano\/crea/.test(path) ||
        /\/importa(-pdf)?(\/|$)/.test(path)) return 'form';

    // builders & wizards — sidebar list + canvas
    if (/\/(wizard|crea|builder)(\/|$)/.test(path) ||
        /\/modelli\/(nuovo|\d+)(\/|$)/.test(path) ||
        /\/sessione\/\d+/.test(path)) return 'builder';

    // card-grid catalogues — filter chips + cards
    if (/^\/allenamenti\/?$/.test(path)) return role === 'client' ? 'list' : 'cards';
    if (/^\/nutrizione\/(piani|integratori)\/?$/.test(path) ||
        /^\/check\/(modelli|trova-coach)\/?$/.test(path)) return 'cards';
    if (/^\/abbonamenti\/?$/.test(path)) return role === 'client' ? 'cards' : 'cards-kpi';

    // dashboards — KPI grid + two columns (client home is a card trio)
    if (path === '/' || /\/dashboard\/?$/.test(path))
      return role === 'client' ? 'cards' : 'dashboard';
    if (/^\/check\/?$/.test(path)) return role === 'client' ? 'list' : 'dashboard';

    // check history of one client — stacked rows, not a detail split
    if (/^\/check\/cliente\/\d+/.test(path)) return 'list';

    // anything keyed by an id → two-column detail
    if (/\/\d+(\/|$)/.test(path)) return 'detail';

    // list (default) — search toolbar + rows
    return 'list';
  }

  /* ---- markup builders ----------------------------------------------- */
  function rep(html, n) { var s = ''; for (var i = 0; i < n; i++) s += html; return s; }

  // Page header: eyebrow + title + subtitle + bronze rule, with optional
  // right-aligned action buttons — matches the al-eyebrow/al-h-1/al-rule-bronze
  // header that opens almost every page.
  function head(actions) {
    return '<div class="al-pageskel-head">' +
             '<div class="al-pageskel-head-main">' +
               '<div class="al-skel al-pageskel-eyebrow"></div>' +
               '<div class="al-skel al-pageskel-title"></div>' +
               '<div class="al-skel al-pageskel-sub"></div>' +
               '<div class="al-pageskel-rule"></div>' +
             '</div>' +
             (actions ? '<div class="al-pageskel-head-actions">' +
               rep('<div class="al-skel al-pageskel-btn"></div>', actions) + '</div>' : '') +
           '</div>';
  }

  function kpi() {
    return '<div class="al-pageskel-panel al-pageskel-kpi">' +
             '<div class="al-skel"></div><div class="al-skel"></div><div class="al-skel"></div></div>';
  }
  function row() {
    return '<div class="al-pageskel-row">' +
             '<div class="al-skel al-skel-circle al-skel-circle-md"></div>' +
             '<div class="al-pageskel-row-main"><div class="al-skel"></div><div class="al-skel"></div></div>' +
             '<div class="al-skel al-skel-line" style="width:64px;border-radius:999px;flex:none"></div>' +
           '</div>';
  }
  function card() {
    return '<div class="al-pageskel-panel al-pageskel-cardhead">' +
             '<div class="al-skel"></div><div class="al-skel"></div><div class="al-skel"></div></div>';
  }
  function para() {
    return '<div class="al-pageskel-para">' + rep('<div class="al-skel"></div>', 4) + '</div>';
  }
  function field() {
    return '<div class="al-pageskel-field">' +
             '<div class="al-skel"></div><div class="al-skel"></div></div>';
  }
  function bubble(side) {
    return '<div class="al-pageskel-bubble al-pageskel-bubble-' + side + '">' +
             '<div class="al-skel"></div></div>';
  }
  function chips() {
    return '<div class="al-pageskel-chips">' +
             rep('<div class="al-skel al-pageskel-chip"></div>', 4) + '</div>';
  }
  function chart() {
    return '<div class="al-pageskel-panel al-pageskel-chart">' +
             '<div class="al-skel"></div><div class="al-skel"></div></div>';
  }
  function setcard() {
    return '<div class="al-pageskel-panel al-pageskel-setcard">' +
             '<div class="al-skel al-skel-circle al-skel-circle-md"></div>' +
             '<div class="al-pageskel-row-main"><div class="al-skel"></div><div class="al-skel"></div></div>' +
           '</div>';
  }

  function panel(inner) { return '<div class="al-pageskel-panel" style="padding:0">' + inner + '</div>'; }

  function build(variant) {
    if (variant === 'dashboard') {
      return head(2) +
        '<div class="al-pageskel-kpis">' + rep(kpi(), 4) + '</div>' +
        '<div class="al-pageskel-cols">' +
          panel(rep(row(), 5)) + panel(rep(row(), 4)) +
        '</div>';
    }
    if (variant === 'detail') {
      return head(1) +
        '<div class="al-pageskel-cols">' +
          '<div class="al-pageskel-panel">' + para() +
            '<div class="al-pageskel-grid" style="margin-top:24px">' + rep(card(), 2) + '</div></div>' +
          panel(rep(row(), 4)) +
        '</div>';
    }
    if (variant === 'form') {
      return head(0) +
        '<div class="al-pageskel-panel al-pageskel-form">' + rep(field(), 6) + '</div>';
    }
    if (variant === 'builder') {
      return head(2) +
        '<div class="al-pageskel-builder">' +
          panel(rep(row(), 6)) +
          '<div class="al-pageskel-panel">' +
            '<div class="al-pageskel-grid">' + rep(card(), 4) + '</div></div>' +
        '</div>';
    }
    if (variant === 'calendar') {
      return head(2) +
        '<div class="al-pageskel-agenda">' +
          '<div class="al-pageskel-panel al-pageskel-agendaside">' +
            '<div class="al-skel al-pageskel-sidetitle"></div>' +
            '<div class="al-pageskel-minical">' + rep('<div class="al-skel"></div>', 35) + '</div>' +
            rep(row(), 3) +
          '</div>' +
          '<div class="al-pageskel-panel">' +
            '<div class="al-pageskel-calhead"><div class="al-skel"></div><div class="al-skel"></div></div>' +
            '<div class="al-pageskel-calgrid">' + rep('<div class="al-skel"></div>', 35) + '</div>' +
          '</div>' +
        '</div>';
    }
    if (variant === 'analytics') {
      return head(1) +
        '<div class="al-pageskel-kpis">' + rep(kpi(), 4) + '</div>' +
        '<div class="al-pageskel-chartgrid al-pageskel-chartgrid-2">' + rep(chart(), 2) + '</div>';
    }
    if (variant === 'charts') {
      return head(1) +
        '<div class="al-pageskel-toolbar"><div class="al-skel"></div><div class="al-skel"></div></div>' +
        '<div class="al-pageskel-chartgrid">' + rep(chart(), 3) + '</div>';
    }
    if (variant === 'cards' || variant === 'cards-kpi') {
      return head(1) +
        (variant === 'cards-kpi' ? '<div class="al-pageskel-kpis">' + rep(kpi(), 4) + '</div>' : '') +
        chips() +
        '<div class="al-pageskel-grid">' + rep(card(), 6) + '</div>';
    }
    if (variant === 'settings') {
      return head(0) +
        '<div class="al-pageskel-setgrid">' + rep(setcard(), 6) + '</div>';
    }
    if (variant === 'profile') {
      return head(1) +
        '<div class="al-pageskel-profile">' +
          '<div class="al-pageskel-panel">' +
            '<div class="al-pageskel-chatbar" style="margin-bottom:20px">' +
              '<div class="al-skel al-skel-circle al-skel-circle-md"></div>' +
              '<div class="al-pageskel-row-main"><div class="al-skel"></div><div class="al-skel"></div></div>' +
            '</div>' + rep(field(), 4) +
          '</div>' +
          panel(rep(row(), 4)) +
        '</div>';
    }
    if (variant === 'timeline') {
      return head(0) +
        '<div class="al-pageskel-kpis al-pageskel-kpis-3">' + rep(kpi(), 3) + '</div>' +
        panel(rep(row(), 6));
    }
    if (variant === 'chat') {
      return '<div class="al-pageskel-chat">' +
          '<div class="al-pageskel-chatbar">' +
            '<div class="al-skel al-skel-circle al-skel-circle-md"></div>' +
            '<div class="al-pageskel-row-main"><div class="al-skel"></div><div class="al-skel"></div></div>' +
          '</div>' +
          '<div class="al-pageskel-chatbody">' +
            bubble('in') + bubble('out') + bubble('in') + bubble('in') + bubble('out') +
          '</div>' +
          '<div class="al-pageskel-chatcompose">' +
            '<div class="al-skel"></div><div class="al-skel al-pageskel-btn"></div>' +
          '</div>' +
        '</div>';
    }
    // list (default)
    return head(1) +
      '<div class="al-pageskel-toolbar"><div class="al-skel"></div><div class="al-skel"></div></div>' +
      panel(rep(row(), 8));
  }

  /* ---- show ---------------------------------------------------------- */
  function show(variant) {
    var page = document.querySelector('.al-page');
    if (!page || shown) return;
    shown = true;
    page.innerHTML = '<div class="al-pageskel al-pageskel-' + variant + '">' + build(variant) + '</div>';
    var main = document.querySelector('main.al-canvas');
    if (main) main.scrollTop = 0;
  }

  /* ---- click interception ------------------------------------------- */
  function eligible(a, e) {
    if (e.defaultPrevented || e.button !== 0) return false;
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return false;
    if (a.target && a.target !== '' && a.target !== '_self') return false;
    if (a.hasAttribute('download') || a.dataset.noSkel !== undefined) return false;
    if (a.closest('[data-no-skel]')) return false;

    var href = a.getAttribute('href') || '';
    if (!href || href[0] === '#') return false;
    if (/^(javascript:|mailto:|tel:|blob:|data:)/i.test(href)) return false;

    var url;
    try { url = new URL(a.href, location.href); } catch (_) { return false; }
    if (url.origin !== location.origin) return false;
    // same page (only hash / identical) → no transition
    if (url.pathname === location.pathname && url.search === location.search) return false;
    return true;
  }

  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('a[href]');
    if (!a || !eligible(a, e)) return;
    var path = new URL(a.href, location.href).pathname;
    var variant = variantFor(path);
    clearTimeout(timer);
    timer = setTimeout(function () { show(variant); }, DELAY);
  }, true);

  // Cancel a pending skeleton if the page is being restored from bfcache.
  window.addEventListener('pageshow', function () { clearTimeout(timer); shown = false; });
})();
