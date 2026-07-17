/* ============================================================
   ATHLYNK — componenti nuovi sito multi-pagina
   film scrub (hero landing) · demo reel · cinematic scroll
   ============================================================ */
(() => {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  /* progresso 0→1 di un elemento "track" rispetto a uno stage sticky */
  function trackProgress(track, stage) {
    const r = track.getBoundingClientRect();
    const stickyTop = parseFloat(getComputedStyle(stage).top) || 0;
    const scrollable = r.height - stage.offsetHeight;
    if (scrollable <= 0) return 0;
    return clamp((stickyTop - r.top) / scrollable, 0, 1);
  }

  /* ============================================================
     FILM — hero landing: scrub video su scroll + takeover logo
     Struttura: .film > .film-track > .film-stage (sticky)
       .film-stage > video.film-video + didascalie .film-cap[data-fs]
       + .film-finale (logo A → Athlynk + slogan)
     Timeline (p = progresso track):
       0.00–0.66  scrub video (3 scene)
       0.60–0.78  scrim scurisce
       0.70–0.80  mark (logo A) compare
       0.80–0.92  "thlynk" si rivela da sinistra a destra
       0.90–1.00  slogan + CTA
     ============================================================ */
  const film = document.querySelector(".film");
  if (film) {
    const track = film.querySelector(".film-track");
    const stage = film.querySelector(".film-stage");
    const video = film.querySelector(".film-video");
    const caps = [...film.querySelectorAll(".film-cap")];
    const finale = film.querySelector(".film-finale");
    const hint = film.querySelector(".film-hint");

    const VIDEO_END = 0.66;         // quota di scroll dedicata al video
    const SCENES = caps.length || 3;

    /* canvas: su iOS un <video> in pausa non ridipinge al cambio di
       currentTime; drawImage legge sempre il frame decodificato. */
    let canvas = null, ctx = null;
    const useVideo = !reduceMotion && !!video && !!video.canPlayType &&
                     !!video.canPlayType("video/mp4");
    if (useVideo) {
      canvas = document.createElement("canvas");
      canvas.className = "film-canvas";
      canvas.setAttribute("aria-hidden", "true");
      video.after(canvas);
      ctx = canvas.getContext("2d");
    }
    film.classList.add(useVideo ? "is-video" : "is-static");

    function paintFrame() {
      if (!ctx || !video.videoWidth) return;
      if (canvas.width !== video.videoWidth) {
        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;
      }
      try { ctx.drawImage(video, 0, 0, canvas.width, canvas.height); } catch (e) {}
    }

    let duration = 0;
    let activeScene = -1;

    function update() {
      const p = trackProgress(track, stage);

      /* 1) scrub video */
      if (useVideo && duration > 0) {
        const vp = clamp(p / VIDEO_END, 0, 1);
        const t = Math.min(vp * duration, duration - 0.05);
        if (Math.abs(t - video.currentTime) > 0.03) {
          try { video.currentTime = t; } catch (e) {}
        }
        paintFrame();
      }

      /* 2) didascalie di scena */
      const sc = p >= VIDEO_END ? -1 : Math.min(SCENES - 1, Math.floor((p / VIDEO_END) * SCENES));
      if (sc !== activeScene) {
        activeScene = sc;
        caps.forEach((c, i) => c.classList.toggle("is-active", i === sc));
      }

      /* 3) takeover finale — variabili CSS pilotate dal progresso */
      const scrim = clamp((p - 0.60) / 0.18, 0, 1);
      const mark  = clamp((p - 0.70) / 0.10, 0, 1);
      const name  = clamp((p - 0.80) / 0.12, 0, 1);
      const tail  = clamp((p - 0.90) / 0.10, 0, 1);
      stage.style.setProperty("--scrim", scrim.toFixed(3));
      stage.style.setProperty("--mark", mark.toFixed(3));
      stage.style.setProperty("--name", name.toFixed(3));
      stage.style.setProperty("--tail", tail.toFixed(3));
      if (finale) finale.classList.toggle("is-live", p > 0.68);
      if (hint) hint.classList.toggle("is-hidden", p > 0.04);
    }

    if (useVideo) {
      const narrowQ = matchMedia("(max-width: 900px)");
      video.preload = "auto";
      video.src = narrowQ.matches
        ? (video.dataset.srcNarrow || video.dataset.srcWide)
        : (video.dataset.srcWide || video.dataset.srcNarrow);
      video.addEventListener("loadedmetadata", () => {
        duration = video.duration || 0;
        const pl = video.play();               // prime: iOS dipinge i seek dopo play→pause
        if (pl && pl.then) pl.then(() => video.pause()).catch(() => {});
        update();
      }, { once: true });
      video.addEventListener("loadeddata", update, { once: true });
      video.addEventListener("seeked", paintFrame);
      video.addEventListener("error", () => {
        film.classList.remove("is-video");
        film.classList.add("is-static");
      }, { once: true });
      video.load();
    }

    let tick = false;
    const onScroll = () => {
      if (!tick) { tick = true; requestAnimationFrame(() => { update(); tick = false; }); }
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll, { passive: true });
    update();
  }

  /* ============================================================
     DEMO REEL — slideshow automatico di screenshot reali
     .reel[data-interval] > .reel-frame > img.reel-slide* + .reel-dots
     ============================================================ */
  document.querySelectorAll(".reel").forEach((reel) => {
    const slides = [...reel.querySelectorAll(".reel-slide")];
    if (slides.length < 2) return;
    const dotsBox = reel.querySelector(".reel-dots");
    const labelEl = reel.querySelector(".reel-label");
    /* the console rail is shared across slides: move its highlight with the
       slide so the mockup behaves like the real app being clicked through */
    const navs = [...reel.querySelectorAll(".app-rail [data-nav]")];
    const dots = slides.map((s, i) => {
      const d = document.createElement("button");
      d.type = "button";
      d.className = "reel-dot";
      d.setAttribute("aria-label", `Vai alla schermata ${i + 1}`);
      d.addEventListener("click", () => go(i, true));
      dotsBox && dotsBox.appendChild(d);
      return d;
    });
    let idx = 0, timer = null;
    const every = parseInt(reel.dataset.interval, 10) || 3200;

    function go(i, manual) {
      idx = (i + slides.length) % slides.length;
      slides.forEach((s, k) => s.classList.toggle("is-active", k === idx));
      dots.forEach((d, k) => d.classList.toggle("is-active", k === idx));
      navs.forEach((n) => n.classList.toggle("is-active", +n.dataset.nav === idx));
      if (labelEl) labelEl.textContent = slides[idx].dataset.label || "";
      if (manual) restart();
    }
    function restart() {
      if (timer) clearInterval(timer);
      if (!reduceMotion) timer = setInterval(() => go(idx + 1), every);
    }
    /* parte solo quando visibile */
    const io = new IntersectionObserver((es) => {
      es.forEach((e) => {
        if (e.isIntersecting) restart();
        else if (timer) { clearInterval(timer); timer = null; }
      });
    }, { threshold: 0.25 });
    io.observe(reel);
    go(0);
  });

  /* ============================================================
     CINEMATIC — stage sticky: il device/frame parte pieno schermo
     e scala scendendo, il testo entra a step (stile CinematicHero)
     .cine > .cine-track > .cine-stage (sticky)
       elementi con [data-cine="frame"] e step [data-cine-step]
     ============================================================ */
  document.querySelectorAll(".cine").forEach((cine) => {
    const track = cine.querySelector(".cine-track");
    const stage = cine.querySelector(".cine-stage");
    if (!track || !stage) return;
    const steps = [...cine.querySelectorAll("[data-cine-step]")];
    let tick = false;

    function update() {
      const p = trackProgress(track, stage);
      stage.style.setProperty("--cp", p.toFixed(4));
      const n = steps.length;
      steps.forEach((s, i) => {
        /* ogni step vive in una finestra di progresso; l'ultimo resta */
        const start = n ? i / n : 0;
        const end = n ? (i + 1) / n : 1;
        const on = p >= start && (i === n - 1 ? true : p < end) && p >= 0.001;
        s.classList.toggle("is-active", on && p >= start);
      });
    }
    const onScroll = () => {
      if (!tick) { tick = true; requestAnimationFrame(() => { update(); tick = false; }); }
    };
    if (reduceMotion) {
      stage.style.setProperty("--cp", "1");
      steps.forEach((s) => s.classList.add("is-active"));
      return;
    }
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll, { passive: true });
    update();
  });

  /* ============================================================
     LIGHTBOX screenshot — click per ingrandire (pagine interne)
     ============================================================ */
  const shots = [...document.querySelectorAll("[data-zoom]")];
  if (shots.length) {
    const box = document.createElement("div");
    box.className = "zoombox";
    box.hidden = true;
    box.innerHTML = '<button class="zoombox-close" aria-label="Chiudi">✕</button><img alt="">';
    document.body.appendChild(box);
    const img = box.querySelector("img");
    function close() { box.hidden = true; document.body.classList.remove("modal-open"); }
    shots.forEach((el) => {
      el.style.cursor = "zoom-in";
      el.addEventListener("click", () => {
        img.src = el.dataset.zoom || el.currentSrc || el.src;
        img.alt = el.alt || "";
        box.hidden = false;
        document.body.classList.add("modal-open");
      });
    });
    box.addEventListener("click", close);
    document.addEventListener("keydown", (e) => { if (e.key === "Escape" && !box.hidden) close(); });
  }
})();
