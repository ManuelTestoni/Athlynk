/* skeleton_nav.js — Athlynk
   Page-transition skeletons for the SSR app. On a full-page internal
   navigation the browser keeps the old page frozen until the next
   document arrives from the server (DB query + network latency). We
   intercept the click, and after a short grace period paint a section-
   shaped skeleton into .al-page so the wait reads as "instant".

   SAFE BOUNDARY: no fetch, no form submit, no state. Never calls
   preventDefault — the real navigation always proceeds untouched.
   The injected skeleton is discarded when the new document commits. */
(function () {
  'use strict';

  var DELAY = 140;            // ms before the skeleton shows (skips fast loads)
  var timer = null;
  var shown = false;

  /* ---- variant routing ---------------------------------------------- */
  function variantFor(path) {
    if (path === '/' || /\/dashboard\/?$/.test(path) || /(^|\/)agenda(\/|$)/.test(path)) {
      return 'dashboard';
    }
    if (/\/\d+(\/|$)/.test(path) ||
        /(create|edit|detail|wizard|builder|session|profilo|percorso|checkout|plan|registra|me)(\/|$)/.test(path)) {
      return 'detail';
    }
    return 'list';
  }

  /* ---- markup builders ---------------------------------------------- */
  function head() {
    return '<div class="al-pageskel-head">' +
             '<div class="al-skel al-pageskel-eyebrow"></div>' +
             '<div class="al-skel al-pageskel-title"></div>' +
             '<div class="al-skel al-pageskel-sub"></div>' +
           '</div>';
  }
  function rep(html, n) { var s = ''; for (var i = 0; i < n; i++) s += html; return s; }

  function stat() {
    return '<div class="al-pageskel-panel al-pageskel-stat">' +
             '<div class="al-skel"></div><div class="al-skel"></div></div>';
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

  function build(variant) {
    if (variant === 'dashboard') {
      return head() +
        '<div class="al-pageskel-stats">' + rep(stat(), 4) + '</div>' +
        '<div class="al-pageskel-cols">' +
          '<div class="al-pageskel-panel" style="padding:0">' + rep(row(), 5) + '</div>' +
          '<div class="al-pageskel-panel" style="padding:0">' + rep(row(), 4) + '</div>' +
        '</div>';
    }
    if (variant === 'detail') {
      return head() +
        '<div class="al-pageskel-cols">' +
          '<div class="al-pageskel-panel">' + para() +
            '<div class="al-pageskel-grid" style="margin-top:24px">' + rep(card(), 2) + '</div></div>' +
          '<div class="al-pageskel-panel" style="padding:0">' + rep(row(), 4) + '</div>' +
        '</div>';
    }
    // list (default)
    return head() +
      '<div class="al-pageskel-toolbar"><div class="al-skel"></div><div class="al-skel"></div></div>' +
      '<div class="al-pageskel-panel" style="padding:0">' + rep(row(), 8) + '</div>';
  }

  /* ---- show ---------------------------------------------------------- */
  function show(variant) {
    var page = document.querySelector('.al-page');
    if (!page || shown) return;
    shown = true;
    page.innerHTML = '<div class="al-pageskel">' + build(variant) + '</div>';
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
