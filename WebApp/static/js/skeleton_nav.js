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
     Order matters: most specific families first. */
  function variantFor(path) {
    // chat conversation — message bubbles + composer
    if (/^\/chat\/\d+/.test(path)) return 'chat';

    // settings & simple stacked forms (before builder: anamnesi/crea is a form)
    if (/^\/(impostazioni|profilo)(\/|$)/.test(path) ||
        /\/(registra|modifica)(\/|$)/.test(path) ||
        /\/anamnesi\/crea/.test(path)) return 'form';

    // builders & wizards — sidebar list + canvas
    if (/\/(wizard|crea|builder)(\/|$)/.test(path) ||
        /\/modelli\/(nuovo|\d+)(\/|$)/.test(path) ||
        /\/sessione\/\d+/.test(path)) return 'builder';

    // dashboards — KPI grid + two columns
    if (path === '/' || /\/dashboard\/?$/.test(path) ||
        /^\/agenda\/?$/.test(path) ||
        path === '/check/' || /^\/check\/andamento/.test(path)) return 'dashboard';

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
