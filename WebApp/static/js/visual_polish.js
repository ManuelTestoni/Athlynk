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

    // 6) Staggered reveal — cascade repeated content (rows/cards/list items)
    //    into view. Pure class/CSS-var toggles, no business logic.
    //    Opt-in: [data-stagger] container. Auto: .al-table with a <tbody>.
    //    Re-scanned on alpine:initialized and on DOM mutations (segMo, below)
    //    so content rendered by Alpine x-for after an async fetch is armed too.
    var scanStagger = function () {};
    if (!reducedMotion && 'IntersectionObserver' in window) {
      var STAGGER_CAP = 24; // beyond this, children share the final delay
      var staggerIO = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (!e.isIntersecting) return;
          e.target.classList.add('is-in');
          staggerIO.unobserve(e.target);
        });
      }, { threshold: 0.12, rootMargin: '0px 0px -6% 0px' });

      var armEl = function (el, kids) {
        if (!kids || !kids.length) return;
        // Always refresh --i on whatever children currently exist: a loading
        // placeholder row (skeleton/empty-state) can get armed first, and the
        // real rows that replace it need their own index recomputed — CSS
        // applies the animation to newly-inserted rows automatically as long
        // as --i and .al-armed/.is-in are correct at insertion time.
        for (var i = 0; i < kids.length; i++) {
          kids[i].style.setProperty('--i', Math.min(i, STAGGER_CAP));
        }
        if (!el.classList.contains('al-armed')) {
          el.classList.add('al-armed');
          staggerIO.observe(el);
        }
      };

      scanStagger = function () {
        // Auto-detect card grids: any container with >=2 direct .al-card
        // children is a list — arm it like a table. Skip ones whose children
        // already animate via .al-reveal (base.html) to avoid double motion.
        var seenParents = [];
        document.querySelectorAll('.al-card').forEach(function (card) {
          var p = card.parentElement;
          if (!p || seenParents.indexOf(p) !== -1) return;
          seenParents.push(p);
          if (p.hasAttribute('data-stagger') || p.classList.contains('al-table')) return;
          var cards = 0, j;
          for (j = 0; j < p.children.length; j++) {
            if (p.children[j].classList.contains('al-card')) cards++;
          }
          if (cards < 2) return;
          if (p.querySelector(':scope > .al-reveal, :scope > .al-card.al-reveal')) return;
          p.setAttribute('data-stagger', '');
        });

        document.querySelectorAll('[data-stagger]').forEach(function (el) {
          armEl(el, el.children);
        });
        document.querySelectorAll('.al-table').forEach(function (tbl) {
          var body = tbl.tBodies && tbl.tBodies[0];
          if (body) armEl(tbl, body.rows);
        });
      };

      scanStagger();
      document.addEventListener('alpine:initialized', scanStagger);
    }

    // 7) Count-up — numeric values tick from 0 to target as they enter view.
    //    Opt-in: [data-countup="<number>"] (dot decimal). Optional
    //    data-countup-prefix / data-countup-suffix. Display-only.
    if (!reducedMotion && 'IntersectionObserver' in window) {
      var fmt = function (n, decimals) {
        return n.toLocaleString('it-IT', {
          minimumFractionDigits: decimals,
          maximumFractionDigits: decimals
        });
      };
      var runCountUp = function (el) {
        var target = parseFloat(el.dataset.countup);
        if (isNaN(target)) return;
        var raw = el.dataset.countup.trim();
        var dot = raw.indexOf('.');
        var decimals = dot === -1 ? 0 : raw.length - dot - 1;
        var prefix = el.dataset.countupPrefix || '';
        var suffix = el.dataset.countupSuffix || '';
        var dur = 1100, start = null;
        el.classList.add('is-counting');
        var step = function (ts) {
          if (start === null) start = ts;
          var p = Math.min((ts - start) / dur, 1);
          var eased = 1 - Math.pow(1 - p, 3); // ease-out cubic
          el.textContent = prefix + fmt(target * eased, decimals) + suffix;
          if (p < 1) {
            window.requestAnimationFrame(step);
          } else {
            el.textContent = prefix + fmt(target, decimals) + suffix;
            el.classList.remove('is-counting');
          }
        };
        window.requestAnimationFrame(step);
      };
      var countIO = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (!e.isIntersecting) return;
          runCountUp(e.target);
          countIO.unobserve(e.target);
        });
      }, { threshold: 0.5 });
      document.querySelectorAll('[data-countup]').forEach(function (el) {
        countIO.observe(el);
      });
    }

    // 8) Filter sliding pill — the active indicator glides between segments
    //    of any segmented control: the standard .al-filter chips and the
    //    .va-segctl chart-type switchers (Istogramma / Linea / Radar, metric
    //    switchers, etc.). Pure positioning of a cosmetic element; reads the
    //    .is-active marker toggled by the app/Alpine.
    function attachSlider(filter, activeSel) {
      if (filter.classList.contains('has-slider')) return;

      var slider = document.createElement('span');
      slider.className = 'al-filter-slider';
      slider.setAttribute('aria-hidden', 'true');
      filter.insertBefore(slider, filter.firstChild);
      filter.classList.add('has-slider');

      var placed = false; // first successful placement never animates
      function place(animate) {
        var chip = filter.querySelector(activeSel);
        if (!chip) { slider.classList.remove('is-ready'); return; }
        var doAnimate = animate && placed;
        if (!doAnimate) slider.style.transition = 'none';
        slider.style.width = chip.offsetWidth + 'px';
        slider.style.height = chip.offsetHeight + 'px';
        slider.style.transform =
          'translate(' + chip.offsetLeft + 'px,' + chip.offsetTop + 'px)';
        slider.classList.toggle(
          'is-bronze',
          chip.classList.contains('is-bronze') || chip.dataset.tone === 'bronze'
        );
        slider.classList.add('is-ready');
        if (!doAnimate) {
          void slider.offsetWidth; // flush, then restore transition
          slider.style.transition = '';
        }
        placed = true;
      }

      // React to active-chip changes and to chips rendered later by Alpine.
      // Ignore mutations on the slider itself to avoid a feedback loop.
      var mo = new MutationObserver(function (muts) {
        for (var i = 0; i < muts.length; i++) {
          if (muts[i].target !== slider) { place(true); return; }
        }
      });
      mo.observe(filter, {
        subtree: true,
        childList: true,
        attributes: true,
        attributeFilter: ['class', 'aria-selected']
      });

      // Initial placement — retried across frames for late Alpine renders.
      place(false);
      window.requestAnimationFrame(function () { place(false); });
      setTimeout(function () { place(false); }, 80);

      // Built while hidden (e.g. inside x-cloak/x-show): offsetWidth is 0 then,
      // so the active chip looks unstyled until first click. Re-place once the
      // control actually becomes visible.
      if ('IntersectionObserver' in window) {
        new IntersectionObserver(function (entries) {
          if (entries.some(function (e) { return e.isIntersecting; })) place(false);
        }).observe(filter);
      }

      var rzTicking = false;
      window.addEventListener('resize', function () {
        if (rzTicking) return;
        rzTicking = true;
        window.requestAnimationFrame(function () { place(false); rzTicking = false; });
      }, { passive: true });
    }

    function scanSliders(root) {
      if (!root || !root.querySelectorAll) return;
      var self = (root.matches ? root : null);
      if (self && self.matches('.al-filter:not(.has-slider)')) {
        attachSlider(self, '.al-filter-chip.is-active, .al-filter-chip[aria-selected="true"]');
      }
      if (self && self.matches('.va-segctl:not(.has-slider)')) {
        attachSlider(self, 'button.is-active');
      }
      root.querySelectorAll('.al-filter:not(.has-slider)').forEach(function (f) {
        attachSlider(f, '.al-filter-chip.is-active, .al-filter-chip[aria-selected="true"]');
      });
      root.querySelectorAll('.va-segctl:not(.has-slider)').forEach(function (f) {
        attachSlider(f, 'button.is-active');
      });
    }

    scanSliders(document);
    window.requestAnimationFrame(function () { scanSliders(document); });
    setTimeout(function () { scanSliders(document); }, 120);

    // Teleported drawers (volume / exercise-stats) mount their .va-segctl into
    // <body> after Alpine inits — watch for them and attach lazily.
    var segMo = new MutationObserver(function (muts) {
      var sawElement = false;
      for (var i = 0; i < muts.length; i++) {
        var added = muts[i].addedNodes;
        for (var j = 0; j < added.length; j++) {
          if (added[j].nodeType === 1) {
            scanSliders(added[j]);
            sawElement = true;
          }
        }
      }
      if (sawElement) scanStagger();
    });
    segMo.observe(document.body, { childList: true, subtree: true });
  });
})();
