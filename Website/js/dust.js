/* ============================================================
   ATHLYNK — gold dust
   Motes of gold and silver drifting through a marble hall.
   Canvas field: density scales with viewport, pauses when the
   tab is hidden, and never runs under prefers-reduced-motion.
   ============================================================ */
(function () {
  "use strict";

  var canvas = document.querySelector(".dust");
  if (!canvas || !canvas.getContext) return;

  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
  if (reduce.matches) { canvas.remove(); return; }

  var ctx = canvas.getContext("2d", { alpha: true });
  var motes = [];
  var raf = null;
  var w = 0, h = 0, dpr = 1;

  // pointer drift: the field leans toward the cursor, like dust in a draught
  var pointer = { x: 0.5, y: 0.5, tx: 0.5, ty: 0.5 };

  var PALETTE = [
    "255, 224, 102",  // gold
    "232, 194, 74",   // deep gold
    "201, 210, 222",  // silver
    "91, 137, 182"    // azure
  ];

  function rand(min, max) { return min + Math.random() * (max - min); }

  function count() {
    // keep the field sparse on small screens and on weak devices
    var area = window.innerWidth * window.innerHeight;
    var n = Math.round(area / 22000);
    if (navigator.hardwareConcurrency && navigator.hardwareConcurrency <= 4) n = Math.round(n * 0.6);
    return Math.max(18, Math.min(n, 90));
  }

  function makeMote() {
    return {
      x: rand(0, w),
      y: rand(0, h),
      r: rand(0.6, 2.1),
      // slow, mostly upward drift — motes rise through light
      vx: rand(-0.10, 0.10),
      vy: rand(-0.24, -0.05),
      a: rand(0.14, 0.5),
      // each mote breathes at its own rate
      phase: rand(0, Math.PI * 2),
      speed: rand(0.004, 0.012),
      color: PALETTE[Math.floor(rand(0, PALETTE.length))],
      depth: rand(0.3, 1)
    };
  }

  function resize() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    w = window.innerWidth;
    h = window.innerHeight;
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    canvas.style.width = w + "px";
    canvas.style.height = h + "px";
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    var n = count();
    motes = [];
    for (var i = 0; i < n; i++) motes.push(makeMote());
  }

  function frame() {
    ctx.clearRect(0, 0, w, h);

    pointer.x += (pointer.tx - pointer.x) * 0.04;
    pointer.y += (pointer.ty - pointer.y) * 0.04;
    var leanX = (pointer.x - 0.5) * 22;
    var leanY = (pointer.y - 0.5) * 14;

    for (var i = 0; i < motes.length; i++) {
      var m = motes[i];

      m.x += m.vx;
      m.y += m.vy;
      m.phase += m.speed;

      // wrap, so the field never empties
      if (m.y < -6) { m.y = h + 6; m.x = rand(0, w); }
      if (m.x < -6) m.x = w + 6;
      if (m.x > w + 6) m.x = -6;

      var twinkle = 0.55 + Math.sin(m.phase) * 0.45;
      var px = m.x + leanX * m.depth;
      var py = m.y + leanY * m.depth;
      var alpha = m.a * twinkle * m.depth;

      // soft halo — this is what reads as "light", not "dots"
      var g = ctx.createRadialGradient(px, py, 0, px, py, m.r * 4);
      g.addColorStop(0, "rgba(" + m.color + ", " + alpha + ")");
      g.addColorStop(1, "rgba(" + m.color + ", 0)");
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(px, py, m.r * 4, 0, Math.PI * 2);
      ctx.fill();

      // the core
      ctx.fillStyle = "rgba(" + m.color + ", " + (alpha * 0.9) + ")";
      ctx.beginPath();
      ctx.arc(px, py, m.r * 0.5, 0, Math.PI * 2);
      ctx.fill();
    }

    raf = requestAnimationFrame(frame);
  }

  function start() { if (!raf) raf = requestAnimationFrame(frame); }
  function stop() { if (raf) { cancelAnimationFrame(raf); raf = null; } }

  window.addEventListener("pointermove", function (e) {
    pointer.tx = e.clientX / window.innerWidth;
    pointer.ty = e.clientY / window.innerHeight;
  }, { passive: true });

  var rt = null;
  window.addEventListener("resize", function () {
    clearTimeout(rt);
    rt = setTimeout(resize, 180);
  }, { passive: true });

  document.addEventListener("visibilitychange", function () {
    if (document.hidden) stop(); else start();
  });

  // stop honouring the field if the user turns reduced-motion on mid-session
  reduce.addEventListener("change", function (e) {
    if (e.matches) { stop(); ctx.clearRect(0, 0, w, h); canvas.style.display = "none"; }
    else { canvas.style.display = ""; resize(); start(); }
  });

  resize();
  start();
})();
