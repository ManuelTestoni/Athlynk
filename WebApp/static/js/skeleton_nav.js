/* skeleton_nav.js — Athlynk
   Page-transition skeletons for the SSR app. On a full-page internal
   navigation the browser keeps the old page frozen until the next
   document arrives from the server (DB query + network latency). We
   intercept the click, and after a short grace period paint a skeleton
   shaped like the *destination* page into .al-page so the wait reads
   as "instant".

   The skeleton must mirror the real page 1:1 — same content max-width,
   same column structure, same row/card shapes — so nothing jumps when
   the SSR document commits. Each route family routes to its own
   archetype, and every archetype is wrapped in the same max-width
   container the live page uses (most pages: max-w-7xl mx-auto), so the
   skeleton is centred exactly where the content will land.

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

    // chat conversation — full-bleed header + bubbles + composer
    if (/^\/chat\/\d+/.test(path)) return 'chat';
    // chat index — avatar conversation rows in a flush card (max-w-4xl)
    if (/^\/chat\/?$/.test(path)) return 'chatlist';

    // agenda — mini-cal sidebar + day view (toolbar, hero card, event rows)
    if (/^\/agenda\/?$/.test(path)) return 'agenda';

    // business analytics — KPI row + chart panels
    if (/^\/analisi\/?$/.test(path)) return 'analytics';

    // chart pages — chart card grid
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

    // athlete check inbox — stacked to-do cards + completed table
    if (/^\/check\/i-miei-check\/?$/.test(path)) return 'checklist';

    // settings subpages & simple stacked forms (before builder:
    // anamnesi/crea and piano abbonamento are forms)
    if (/^\/impostazioni\//.test(path) ||
        /\/(registra|modifica)(\/|$)/.test(path) ||
        /\/anamnesi\/crea/.test(path) ||
        /\/abbonamenti\/piano\/crea/.test(path) ||
        /\/importa(-pdf)?(\/|$)/.test(path)) return 'form';

    // builders & wizards — step pills + canvas
    if (/\/(wizard|crea|builder)(\/|$)/.test(path) ||
        /\/modelli\/(nuovo|\d+)(\/|$)/.test(path) ||
        /\/sessione\/\d+/.test(path)) return 'builder';

    // athletes roster — filter bar + data table
    if (/^\/clienti\/?$/.test(path)) return 'table';

    // nutrition library — coach: folder sidebar + card grid;
    // athlete: editorial hero + history (same shell as workouts)
    if (/^\/nutrizione\/piani\/?$/.test(path)) return role === 'client' ? 'clienthero' : 'nutrition';
    // supplement library & check catalogues — filter chips + card grid
    if (/^\/nutrizione\/integratori\/?$/.test(path) ||
        /^\/check\/(modelli|trova-coach)\/?$/.test(path)) return 'cards';

    // workout library — coach: folder sidebar + card grid (same wb-shell
    // layout as the nutrition library, hence sharing its 'nutrition'
    // archetype); athlete: hero + history
    if (/^\/allenamenti\/?$/.test(path)) return role === 'client' ? 'clienthero' : 'nutrition';

    // subscriptions — coach: KPI + tabs + plan grid; athlete: hero + plan grid
    if (/^\/abbonamenti\/?$/.test(path)) return role === 'client' ? 'subsclient' : 'subs';

    // dashboards — coach: KPI grid + two columns; athlete: 3 feature cards
    if (path === '/' || /\/dashboard\/?$/.test(path))
      return role === 'client' ? 'home' : 'dashboard';
    if (/^\/check\/?$/.test(path)) return role === 'client' ? 'checklist' : 'dashboard';

    // check history of one client — stacked rows, not a detail split
    if (/^\/check\/cliente\/\d+/.test(path)) return 'list';

    // anything keyed by an id → two-column detail
    if (/\/\d+(\/|$)/.test(path)) return 'detail';

    // list (default) — search toolbar + rows
    return 'list';
  }

  /* Content max-width per variant — mirrors the live page's wrapper
     (Tailwind max-w-* on the page root). '' means full width inside the
     .al-page padding. */
  function widthFor(variant) {
    switch (variant) {
      case 'chatlist':  return '56rem';   // max-w-4xl
      case 'form':      return '48rem';   // max-w-3xl
      case 'checklist': return '48rem';   // max-w-3xl
      case 'home':      return '72rem';   // max-w-6xl
      case 'timeline':  return '72rem';   // max-w-6xl
      case 'subs':      return '';        // w-full
      case 'chat':      return '';        // full-bleed (own wrapper)
      default:          return '80rem';   // max-w-7xl
    }
  }

  /* ---- markup builders ----------------------------------------------- */
  function rep(html, n) { var s = ''; for (var i = 0; i < n; i++) s += html; return s; }
  function s(cls, style) {
    return '<div class="al-skel' + (cls ? ' ' + cls : '') + '"' +
           (style ? ' style="' + style + '"' : '') + '></div>';
  }

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
  // settings vertical-tab nav item — icon dot + label
  function setnavItem() {
    return '<div class="al-pageskel-setnav-item"><div class="al-skel"></div><div class="al-skel"></div></div>';
  }
  function panel(inner) { return '<div class="al-pageskel-panel" style="padding:0">' + inner + '</div>'; }

  // flush card header bar (title block + "see all" link) — al-card-head
  function cardbar() {
    return '<div class="al-pageskel-cardbar">' +
             '<div class="al-pageskel-cardbar-main"><div class="al-skel"></div><div class="al-skel"></div></div>' +
             '<div class="al-skel al-pageskel-cardbar-link"></div>' +
           '</div>';
  }

  // data-table head strip + body rows (al-table). cols = column count.
  function tableSkel(cols, rows) {
    var th = '<div class="al-pageskel-thead">' + rep(s('', ''), cols) + '</div>';
    var tr = '<div class="al-pageskel-trow">' +
               '<div class="al-pageskel-trow-id">' +
                 '<div class="al-skel al-skel-circle" style="width:28px;height:28px;border-radius:6px;flex:none"></div>' +
                 '<div class="al-pageskel-row-main"><div class="al-skel"></div><div class="al-skel"></div></div>' +
               '</div>' +
               rep('<div class="al-skel al-pageskel-tcell"></div>', cols - 2) +
               '<div class="al-skel al-pageskel-tact"></div>' +
             '</div>';
    return '<div class="al-pageskel-panel al-pageskel-table" style="padding:0">' +
             th + rep(tr, rows) + '</div>';
  }

  // tall library card (workout / supplement / nutrition plan)
  function wcard() {
    return '<div class="al-pageskel-panel al-pageskel-wcard">' +
             '<div class="al-pageskel-wcard-top">' +
               '<div class="al-skel al-pageskel-badge"></div>' +
               '<div class="al-skel al-pageskel-badge"></div>' +
             '</div>' +
             '<div class="al-skel al-pageskel-wcard-title"></div>' +
             '<div class="al-skel al-pageskel-wcard-desc"></div>' +
             '<div class="al-skel al-pageskel-wcard-desc" style="width:70%"></div>' +
             '<div class="al-pageskel-wcard-meta">' +
               '<div class="al-skel"></div><div class="al-skel"></div><div class="al-skel"></div>' +
             '</div>' +
             '<div class="al-pageskel-wcard-foot">' +
               '<div class="al-skel"></div><div class="al-skel al-pageskel-wcard-icon"></div>' +
             '</div>' +
           '</div>';
  }

  // athlete subscription plan card — informational only, no footer/CTA:
  // tag, title, description, price+interval (mirrors client_dashboard.html).
  function plancardClient() {
    return '<div class="al-pageskel-panel al-pageskel-plancard-client">' +
             '<div class="al-skel al-pageskel-plcTag"></div>' +
             '<div class="al-skel al-pageskel-plcTitle"></div>' +
             '<div class="al-skel al-pageskel-plcDesc"></div>' +
             '<div class="al-skel al-pageskel-plcDesc" style="width:70%"></div>' +
             '<div class="al-skel al-pageskel-plcPrice"></div>' +
           '</div>';
  }

  // subscription plan card — head (name + price) + body + footer
  function plancard() {
    return '<div class="al-pageskel-panel al-pageskel-plancard">' +
             '<div class="al-pageskel-plancard-head">' +
               '<div class="al-skel al-pageskel-plancard-name"></div>' +
               '<div class="al-skel al-pageskel-plancard-price"></div>' +
             '</div>' +
             '<div class="al-pageskel-plancard-body">' +
               '<div class="al-skel"></div><div class="al-skel" style="width:80%"></div>' +
               '<div class="al-pageskel-plancard-meta"><div class="al-skel"></div><div class="al-skel"></div></div>' +
             '</div>' +
             '<div class="al-pageskel-plancard-foot"><div class="al-skel"></div><div class="al-skel"></div></div>' +
           '</div>';
  }

  // agenda event row — time | marker | title | tag (matches .agenda-event-row)
  function eventRow() {
    return '<div class="al-pageskel-eventrow">' +
             '<div class="al-skel al-pageskel-evtime"></div>' +
             '<div class="al-skel al-pageskel-evmark"></div>' +
             '<div class="al-pageskel-row-main"><div class="al-skel"></div><div class="al-skel"></div></div>' +
             '<div class="al-skel al-pageskel-evtag"></div>' +
           '</div>';
  }

  // chat-list conversation row — large avatar + 2 lines + right meta
  function clrow() {
    return '<div class="al-pageskel-clrow">' +
             '<div class="al-skel al-skel-circle" style="width:56px;height:56px;border-radius:8px;flex:none"></div>' +
             '<div class="al-pageskel-row-main"><div class="al-skel"></div><div class="al-skel"></div></div>' +
             '<div class="al-pageskel-clmeta"><div class="al-skel"></div></div>' +
           '</div>';
  }

  // numbered form section card: section head + 2-col field grid
  function formcard(n) {
    return '<div class="al-pageskel-panel al-pageskel-formcard">' +
             '<div class="al-pageskel-formcard-head">' +
               '<div class="al-skel al-pageskel-formnum"></div>' +
               '<div class="al-skel al-pageskel-formtitle"></div>' +
             '</div>' +
             '<div class="al-pageskel-fieldgrid">' + rep(field(), n) + '</div>' +
           '</div>';
  }

  // athlete dashboard feature card — title + icon, desc, footer link
  function featcard() {
    return '<div class="al-pageskel-panel al-pageskel-featcard">' +
             '<div class="al-pageskel-featcard-head">' +
               '<div class="al-skel al-pageskel-feattitle"></div>' +
               '<div class="al-skel al-pageskel-featicon"></div>' +
             '</div>' +
             '<div class="al-skel al-pageskel-featdesc"></div>' +
             '<div class="al-skel al-pageskel-featdesc" style="width:60%"></div>' +
             '<div class="al-skel al-pageskel-featlink"></div>' +
           '</div>';
  }

  // athlete editorial dark hero — 2-col grid of stacked lines (workout/nutrition)
  function clientHero() {
    return '<div class="al-pageskel-hero">' +
             '<div class="al-pageskel-herogrid">' +
               '<div class="al-pageskel-herocol">' +
                 '<div class="al-skel al-pageskel-heroeyebrow"></div>' +
                 '<div class="al-skel al-pageskel-herotitle"></div>' +
                 '<div class="al-skel al-pageskel-heroline"></div>' +
                 '<div class="al-skel al-pageskel-heroline" style="width:70%"></div>' +
                 '<div class="al-skel al-pageskel-herobtn"></div>' +
               '</div>' +
               '<div class="al-pageskel-herocol al-pageskel-herostats">' +
                 rep('<div class="al-pageskel-herostat"><div class="al-skel"></div><div class="al-skel"></div></div>', 4) +
               '</div>' +
             '</div>' +
           '</div>';
  }

  // athlete check to-do card (bronze left rail)
  function todoCard() {
    return '<div class="al-pageskel-panel al-pageskel-todo">' +
             '<div class="al-pageskel-todo-main">' +
               '<div class="al-skel al-pageskel-todo-title"></div>' +
               '<div class="al-skel al-pageskel-todo-sub"></div>' +
             '</div>' +
             '<div class="al-skel al-pageskel-todo-btn"></div>' +
           '</div>';
  }

  function build(variant) {
    if (variant === 'dashboard') {
      // header + 4 KPIs + (2fr roster table card | 1fr side list card)
      return head(1) +
        '<div class="al-pageskel-kpis">' + rep(kpi(), 4) + '</div>' +
        '<div class="al-pageskel-cols">' +
          panel(cardbar() + tableSkel(3, 5)) +
          panel(cardbar() + rep(row(), 4)) +
        '</div>';
    }
    if (variant === 'table') {
      // header + search/select filter bar + 7-col data table
      return head(1) +
        '<div class="al-pageskel-filterbar">' +
          '<div class="al-skel al-pageskel-search"></div>' +
          '<div class="al-skel al-pageskel-fsel"></div>' +
          '<div class="al-skel al-pageskel-fsel"></div>' +
        '</div>' +
        tableSkel(7, 7);
    }
    if (variant === 'detail') {
      return head(1) +
        '<div class="al-pageskel-cols">' +
          '<div class="al-pageskel-panel">' + para() +
            '<div class="al-pageskel-grid" style="margin-top:24px">' + rep(wcard(), 2) + '</div></div>' +
          panel(rep(row(), 4)) +
        '</div>';
    }
    if (variant === 'form') {
      return head(0) + formcard(6) +
        '<div style="height:20px"></div>' + formcard(4);
    }
    if (variant === 'builder') {
      // step pills + wide work panel (2-col fields) + preview rail
      return head(1) +
        '<div class="al-pageskel-pills">' + rep('<div class="al-skel al-pageskel-pill"></div>', 4) + '</div>' +
        '<div class="al-pageskel-builder">' +
          '<div class="al-pageskel-panel"><div class="al-pageskel-fieldgrid">' + rep(field(), 6) + '</div></div>' +
          panel(rep(row(), 5)) +
        '</div>';
    }
    if (variant === 'agenda') {
      // mirrors .agenda-shell: sidebar CARD (mini-cal + type filter +
      // upcoming, divided sections) | main CARD (toolbar divider + day view).
      var dow = '<div class="al-pageskel-minical-dow">' + rep(s('', ''), 7) + '</div>';
      var agfilter = '<div class="al-pageskel-agfilter">' +
          '<div class="al-skel al-pageskel-agcheck"></div>' +
          '<div class="al-skel al-pageskel-agswatch"></div>' +
          '<div class="al-skel"></div></div>';
      var agup = '<div class="al-pageskel-agup">' +
          '<div class="al-skel"></div><div class="al-skel"></div><div class="al-skel"></div></div>';
      return head(1) +
        '<div class="al-pageskel-agenda">' +
          '<div class="al-pageskel-panel al-pageskel-agendaside" style="padding:0">' +
            '<div class="al-pageskel-agsec">' +
              '<div class="al-pageskel-minical-head"><div class="al-skel"></div><div class="al-skel"></div></div>' +
              dow +
              '<div class="al-pageskel-minical">' + rep('<div class="al-skel"></div>', 42) + '</div>' +
            '</div>' +
            '<div class="al-pageskel-agsec">' +
              '<div class="al-skel al-pageskel-sidetitle"></div>' + rep(agfilter, 4) +
            '</div>' +
            '<div class="al-pageskel-agsec">' +
              '<div class="al-skel al-pageskel-sidetitle"></div>' + rep(agup, 3) +
            '</div>' +
          '</div>' +
          '<div class="al-pageskel-panel al-pageskel-agendamain" style="padding:0">' +
            '<div class="al-pageskel-agtoolbar">' +
              '<div class="al-pageskel-agtoolbar-left">' +
                '<div class="al-skel al-pageskel-agnav"></div>' +
                '<div class="al-skel al-pageskel-agtitle"></div>' +
              '</div>' +
              '<div class="al-skel al-pageskel-agswitch"></div>' +
            '</div>' +
            '<div class="al-pageskel-agbody">' +
              '<div class="al-pageskel-todaycard">' +
                '<div class="al-skel" style="width:60px;height:9px;margin-bottom:10px"></div>' +
                '<div class="al-skel" style="width:55%;height:26px;margin-bottom:8px"></div>' +
                '<div class="al-skel" style="width:30%;height:11px"></div>' +
              '</div>' +
              '<div class="al-pageskel-events">' + rep(eventRow(), 4) + '</div>' +
            '</div>' +
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
        '<div class="al-pageskel-chartgrid">' + rep(chart(), 3) + '</div>';
    }
    if (variant === 'cards') {
      return head(1) + chips() +
        '<div class="al-pageskel-cardgrid">' + rep(wcard(), 6) + '</div>';
    }
    if (variant === 'nutrition') {
      // folder sidebar + plan card grid (wb-shell)
      return head(1) +
        '<div class="al-pageskel-nutri">' +
          '<div class="al-pageskel-panel al-pageskel-nutriside">' +
            '<div class="al-skel al-pageskel-sidetitle"></div>' +
            rep('<div class="al-pageskel-folderrow"><div class="al-skel"></div><div class="al-skel al-pageskel-foldercount"></div></div>', 5) +
          '</div>' +
          '<div class="al-pageskel-cardgrid">' + rep(wcard(), 6) + '</div>' +
        '</div>';
    }
    if (variant === 'subs') {
      return head(1) +
        '<div class="al-pageskel-kpis">' + rep(kpi(), 4) + '</div>' +
        '<div class="al-pageskel-chips" style="margin-bottom:24px">' +
          rep('<div class="al-skel al-pageskel-chip"></div>', 2) + '</div>' +
        '<div class="al-pageskel-plangrid">' + rep(plancard(), 8) + '</div>';
    }
    if (variant === 'home') {
      // athlete home — header + 3 feature nav cards (md:grid-cols-3)
      return head(0) +
        '<div class="al-pageskel-homegrid">' + rep(featcard(), 3) + '</div>';
    }
    if (variant === 'clienthero') {
      // athlete workout / nutrition — editorial hero + history list
      return head(0) + clientHero() +
        '<div class="al-pageskel-toolbar"><div class="al-skel"></div><div class="al-skel"></div></div>' +
        panel(rep(row(), 6));
    }
    if (variant === 'subsclient') {
      // athlete subscriptions — current-plan hero (status pill + title +
      // desc + price, then 4-stat row) + informational plan card grid
      return head(0) +
        '<div class="al-pageskel-panel al-pageskel-subhero" style="padding:0">' +
          '<div class="al-pageskel-subhero-rule"></div>' +
          '<div class="al-pageskel-subhero-top">' +
            '<div class="al-pageskel-subhero-main">' +
              '<div class="al-skel al-pageskel-subhero-pill"></div>' +
              '<div class="al-skel al-pageskel-subhero-title"></div>' +
              '<div class="al-skel al-pageskel-subhero-desc"></div>' +
            '</div>' +
            '<div class="al-skel al-pageskel-subhero-price"></div>' +
          '</div>' +
          '<div class="al-pageskel-subhero-divider"></div>' +
          '<div class="al-pageskel-substats">' +
            rep('<div class="al-pageskel-substat"><div class="al-skel"></div><div class="al-skel"></div></div>', 4) +
          '</div>' +
        '</div>' +
        '<div class="al-pageskel-plangrid al-pageskel-plangrid-client">' + rep(plancardClient(), 6) + '</div>';
    }
    if (variant === 'checklist') {
      // athlete check inbox — to-do cards + completed table
      return head(0) +
        '<div class="al-skel al-pageskel-sectitle"></div>' +
        '<div class="al-pageskel-todolist">' + rep(todoCard(), 3) + '</div>' +
        '<div class="al-skel al-pageskel-sectitle" style="margin-top:32px"></div>' +
        tableSkel(3, 4);
    }
    if (variant === 'settings') {
      // vertical tab rail (Profilo/Sicurezza/Newsletter/Nutrizione/…) +
      // single form card (section head + 2-col field grid)
      return head(0) +
        '<div class="al-pageskel-settings">' +
          '<div class="al-pageskel-setnav">' + rep(setnavItem(), 6) + '</div>' +
          '<div class="al-pageskel-panel al-pageskel-setmain">' +
            '<div class="al-pageskel-setmain-head"><div class="al-skel"></div><div class="al-skel"></div><div class="al-skel"></div></div>' +
            '<div class="al-pageskel-fieldgrid">' + rep(field(), 4) + '</div>' +
          '</div>' +
        '</div>';
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
    if (variant === 'chatlist') {
      return head(0) +
        '<div class="al-pageskel-panel al-pageskel-cllist" style="padding:0">' +
          rep(clrow(), 6) + '</div>';
    }
    if (variant === 'chat') {
      // Mirrors pages/chat/detail.html: back button, square avatar, name
      // line, right-aligned action button, then bubbles and the composer
      // (paperclip + input + send) with the same asymmetric padding the
      // real page uses to clear the Chiron FAB.
      return '<div class="al-pageskel-chat">' +
          '<div class="al-pageskel-chatbar">' +
            '<div class="al-skel al-pageskel-chatback"></div>' +
            '<div class="al-skel al-skel-circle al-skel-circle-md"></div>' +
            '<div class="al-pageskel-row-main"><div class="al-skel"></div><div class="al-skel"></div></div>' +
            '<div class="al-skel al-pageskel-chatact"></div>' +
          '</div>' +
          '<div class="al-pageskel-chatbody">' +
            bubble('in') + bubble('out') + bubble('in') + bubble('in') + bubble('out') + bubble('out') +
          '</div>' +
          '<div class="al-pageskel-chatcompose">' +
            '<div class="al-skel al-pageskel-chatclip"></div>' +
            '<div class="al-skel al-pageskel-chatinput"></div>' +
            '<div class="al-skel al-pageskel-chatsend"></div>' +
          '</div>' +
        '</div>';
    }
    // list (default) — search toolbar + rows
    return head(1) +
      '<div class="al-pageskel-toolbar"><div class="al-skel"></div><div class="al-skel"></div></div>' +
      panel(rep(row(), 8));
  }

  /* ---- show / restore ------------------------------------------------ */
  var saved = null;            // real .al-page HTML, stashed while a skeleton is up

  function show(variant) {
    var page = document.querySelector('.al-page');
    if (!page || shown) return;
    shown = true;
    saved = page.innerHTML;    // keep the real content so a Back restore can put it back
    var w = widthFor(variant);
    var cls = 'al-pageskel al-pageskel-' + variant + (variant === 'chat' ? ' al-pageskel-bleed' : '');
    var style = w ? ' style="max-width:' + w + ';margin-left:auto;margin-right:auto"' : '';
    page.innerHTML = '<div class="' + cls + '"' + style + '>' + build(variant) + '</div>';
    var main = document.querySelector('main.al-canvas');
    if (main) main.scrollTop = 0;
  }

  // Put the real content back and forget the skeleton. Critical before the page
  // is frozen into the back/forward cache: Safari snapshots the *live* DOM, so a
  // painted skeleton would be restored verbatim on Back — a loading shimmer that
  // never resolves. Re-inserting the saved markup lets Alpine re-init the nodes.
  function restore() {
    clearTimeout(timer);
    if (shown) {
      var page = document.querySelector('.al-page');
      if (page && saved != null) page.innerHTML = saved;
    }
    shown = false;
    saved = null;
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

  // Clean the skeleton up around back/forward-cache transitions. `pagehide`
  // fires just before the page is frozen (or unloaded) — restoring there keeps
  // the cached snapshot clean; `pageshow` covers the restore as a safety net.
  window.addEventListener('pagehide', restore);
  window.addEventListener('pageshow', restore);
})();
