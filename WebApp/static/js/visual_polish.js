/* visual_polish.js — Athlynk
   Purely cosmetic behaviors: class toggles, scroll observers, transform hooks.
   SAFE BOUNDARY: zero business logic. No fetch. No form submit. No state.
   Touches only: dataset flags on <body>, CSS class toggles, inline transform. */
(function () {
  'use strict';

  function onReady(fn) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', fn, { once: true });
    } else {
      fn();
    }
  }

  onReady(function () {
    // 1) Mark page ready so CSS can play the silk reveal.
    document.body.dataset.alPageReady = '1';

    // 2) Meander / divider draw-on-scroll.
    if ('IntersectionObserver' in window) {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) {
            e.target.classList.add('is-drawn');
            io.unobserve(e.target);
          }
        });
      }, { threshold: 0.35, rootMargin: '0px 0px -8% 0px' });

      document.querySelectorAll('[data-draw]').forEach(function (el) {
        io.observe(el);
      });
    } else {
      document.querySelectorAll('[data-draw]').forEach(function (el) {
        el.classList.add('is-drawn');
      });
    }

    // 3) Header scroll-shrink — toggles data-scrolled on body.
    var scrollContainers = [];
    var canvas = document.querySelector('main.al-canvas, .al-canvas');
    if (canvas) scrollContainers.push(canvas);
    scrollContainers.push(window);

    var ticking = false;
    function readScroll() {
      var top = 0;
      if (canvas) top = Math.max(top, canvas.scrollTop || 0);
      top = Math.max(top, window.scrollY || window.pageYOffset || 0);
      document.body.dataset.scrolled = top > 8 ? '1' : '0';
      ticking = false;
    }
    function onScroll() {
      if (ticking) return;
      ticking = true;
      window.requestAnimationFrame(readScroll);
    }
    scrollContainers.forEach(function (s) {
      s.addEventListener('scroll', onScroll, { passive: true });
    });
    readScroll();

    // 4) Magnetic CTA — opt-in via data-magnetic. Pure transform, no business.
    var reducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (!reducedMotion) {
      document.querySelectorAll('[data-magnetic]').forEach(function (el) {
        el.addEventListener('mousemove', function (e) {
          var r = el.getBoundingClientRect();
          var dx = (e.clientX - (r.left + r.width / 2)) * 0.08;
          var dy = (e.clientY - (r.top + r.height / 2)) * 0.12;
          el.style.transform = 'translate(' + dx.toFixed(2) + 'px,' + dy.toFixed(2) + 'px)';
        });
        el.addEventListener('mouseleave', function () {
          el.style.transform = '';
        });
      });
    }

    // 5) Auto-loading flag on submit buttons (visual-only — adds class, does not
    //    prevent or alter submit). Reverts on pageshow (back-forward cache).
    document.addEventListener('submit', function (e) {
      var form = e.target;
      if (!(form instanceof HTMLFormElement)) return;
      var btn = form.querySelector('button[type="submit"], .al-btn[type="submit"]');
      if (btn && !btn.classList.contains('is-loading')) {
        btn.classList.add('is-loading');
      }
    }, true);
    window.addEventListener('pageshow', function () {
      document.querySelectorAll('.al-btn.is-loading').forEach(function (b) {
        b.classList.remove('is-loading');
      });
    });
  });
})();
