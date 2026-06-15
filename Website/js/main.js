/* ============================================================
   ATHLYNK — interactions
   ============================================================ */
(() => {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------- smart sticky header ---------- */
  const header = document.getElementById("siteHeader");
  let lastY = window.scrollY;
  let ticking = false;

  function onScroll() {
    const y = window.scrollY;
    header.classList.toggle("scrolled", y > 24);
    // hide on scroll down, show on scroll up (only past the hero fold)
    if (y > 420 && y > lastY + 6) header.classList.add("hidden");
    else if (y < lastY - 6 || y < 420) header.classList.remove("hidden");
    lastY = y;
    updateParallax(y);
    ticking = false;
  }

  window.addEventListener("scroll", () => {
    if (!ticking) {
      ticking = true;
      requestAnimationFrame(onScroll);
    }
  }, { passive: true });

  /* ---------- mobile nav ---------- */
  const navToggle = document.getElementById("navToggle");
  const mainNav = document.getElementById("mainNav");

  navToggle.addEventListener("click", () => {
    const open = mainNav.classList.toggle("open");
    navToggle.classList.toggle("open", open);
    navToggle.setAttribute("aria-expanded", String(open));
  });

  mainNav.querySelectorAll(".nav-link").forEach((link) => {
    link.addEventListener("click", () => {
      mainNav.classList.remove("open");
      navToggle.classList.remove("open");
      navToggle.setAttribute("aria-expanded", "false");
    });
  });

  /* ---------- active nav link on scroll ---------- */
  const sections = ["hero", "chiron", "studio", "pricing", "about", "faq"]
    .map((id) => document.getElementById(id))
    .filter(Boolean);
  const navLinks = [...document.querySelectorAll(".main-nav .nav-link")];

  const sectionSpy = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      navLinks.forEach((l) =>
        l.classList.toggle("active", l.getAttribute("href") === `#${entry.target.id}`)
      );
    });
  }, { rootMargin: "-40% 0px -55% 0px" });

  sections.forEach((s) => sectionSpy.observe(s));

  /* ---------- reveal on scroll (staggered) ---------- */
  const reveals = [...document.querySelectorAll(".reveal")];
  const revealObserver = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      // stagger siblings revealed in the same batch
      const siblings = entry.target.parentElement
        ? [...entry.target.parentElement.children].filter((c) => c.classList.contains("reveal"))
        : [entry.target];
      const idx = Math.max(0, siblings.indexOf(entry.target));
      entry.target.style.setProperty("--rd", `${Math.min(idx * 0.12, 0.6)}s`);
      entry.target.classList.add("in");
      revealObserver.unobserve(entry.target);
    });
  }, { threshold: 0.18, rootMargin: "0px 0px -8% 0px" });

  reveals.forEach((el) => revealObserver.observe(el));

  /* ---------- parallax (scroll + pointer, hero & chiron) ---------- */
  const parallaxEls = [...document.querySelectorAll("[data-parallax]")];
  let pointerX = 0;
  let pointerY = 0;

  function updateParallax(scrollY) {
    if (reduceMotion) return;
    parallaxEls.forEach((el) => {
      const f = parseFloat(el.dataset.parallax);
      const sy = scrollY * f * -1;
      const px = pointerX * f * 140;
      const py = pointerY * f * 90;
      el.style.transform =
        `${el.classList.contains("hero-ring") || el.classList.contains("chiron-rings") || el.classList.contains("hero-figure")
          ? "translateY(-50%) " : ""}translate3d(${px}px, ${sy + py}px, 0)`;
    });
  }

  if (!reduceMotion && matchMedia("(pointer: fine)").matches) {
    document.addEventListener("pointermove", (e) => {
      pointerX = (e.clientX / window.innerWidth - 0.5);
      pointerY = (e.clientY / window.innerHeight - 0.5);
      if (!ticking) {
        ticking = true;
        requestAnimationFrame(() => { updateParallax(window.scrollY); ticking = false; });
      }
    }, { passive: true });
  }

  /* ---------- forge: blocco di marmo scolpito, scrub guidato dallo scroll ---------- */
  const forge = document.querySelector(".forge");
  if (forge) {
    const track = forge.querySelector(".forge-scroll");
    const stage = forge.querySelector(".forge-stage");
    const media = forge.querySelector(".forge-media");
    const video = forge.querySelector(".forge-video");
    const stills = [...forge.querySelectorAll(".forge-still")];
    const caps = [...forge.querySelectorAll(".forge-cap")];
    const nodes = [...forge.querySelectorAll(".forge-node")];
    const railFill = forge.querySelector(".forge-rail-fill");

    const CP = caps.length || 5;                 // numero di checkpoint (5)
    const LAST = Math.max(stills.length - 1, 1);  // indice ultimo fotogramma (5)

    // RENDERING SU CANVAS — identico per desktop e mobile.
    // Su iOS un <video> in pausa NON ridipinge quando si cambia currentTime (mostra un
    // fotogramma congelato). drawImage() invece legge sempre il frame decodificato, quindi
    // disegnando il video su un canvas lo scrub diventa fluido ovunque, iPhone compreso.
    let ctx = null, canvas = null;
    if (video) {
      canvas = document.createElement("canvas");
      canvas.className = "forge-canvas";
      canvas.setAttribute("aria-hidden", "true");
      canvas.style.cssText =
        "position:absolute;inset:0;width:100%;height:100%;object-fit:contain;z-index:3;" +
        "filter:brightness(0.98) contrast(1.05) drop-shadow(0 30px 60px rgba(0,0,0,0.55));";
      video.after(canvas);
      ctx = canvas.getContext("2d");
    }
    function paintFrame() {
      if (!ctx || !video.videoWidth) return;
      if (canvas.width !== video.videoWidth) {
        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;
      }
      try { ctx.drawImage(video, 0, 0, canvas.width, canvas.height); } catch (e) {}
    }
    if (video) {
      video.addEventListener("seeked", paintFrame);
      video.addEventListener("loadeddata", paintFrame);
    }

    // scrub video su tutti i dispositivi (desktop + mobile), senza reduce-motion e con supporto mp4.
    // su mobile carica la sorgente leggera all-keyframe (forge.m480.mp4) per uno scrub fluido.
    const narrowQ = matchMedia("(max-width: 900px)");
    const useVideo = !reduceMotion && !!video &&
                     !!video.canPlayType && !!video.canPlayType("video/mp4");
    forge.classList.add(useVideo ? "is-video" : "is-stills");
    let videoMode = useVideo; // può tornare false se il browser non sa fare lo scrub

    // stato dichiarato PRIMA del blocco video: setDur() può chiamare update() in modo sincrono
    const stickyTop = parseFloat(getComputedStyle(stage).top) || 0;
    let duration = 0;
    let activeCp = 0;
    let activeStill = -1;

    function progress() {
      const r = track.getBoundingClientRect();
      const scrollable = r.height - stage.offsetHeight;
      if (scrollable <= 0) return 0;
      const p = (stickyTop - r.top) / scrollable;
      return Math.max(0, Math.min(1, p));
    }

    function update() {
      const p = progress();

      // 1) media: scrub del video, oppure crossfade dei fotogrammi (fallback)
      if (videoMode) {
        if (duration > 0) {
          const t = Math.min(p * duration, duration - 0.05);
          if (Math.abs(t - video.currentTime) > 0.03) {
            try { video.currentTime = t; } catch (e) { /* seek non pronto */ }
          }
          paintFrame(); // disegna subito il frame decodificato (iOS non ridipinge il <video>)
        }
      } else {
        const idx = Math.round(p * LAST);
        if (idx !== activeStill) {
          activeStill = idx;
          stills.forEach((s) => s.classList.toggle("is-active", +s.dataset.k === idx));
        }
      }

      // 2) checkpoint attivo (5 segmenti uguali lungo lo scroll)
      const cp = Math.max(1, Math.min(CP, Math.floor(p * CP) + 1));
      if (cp !== activeCp) {
        activeCp = cp;
        caps.forEach((c) => c.classList.toggle("is-active", +c.dataset.cp === cp));
        nodes.forEach((n) => {
          const ci = +n.dataset.cp;
          n.classList.toggle("active", ci === cp);
          n.classList.toggle("passed", ci < cp);
        });
      }

      // 3) riempimento del binario verticale
      if (railFill) railFill.style.height = (p * 100).toFixed(2) + "%";
    }

    // sorgente adatta al viewport: file leggero all-keyframe su mobile, qualità piena su desktop.
    // (è solo la scelta del file: la LOGICA di scrub è identica per mobile e desktop)
    function pickSrc() {
      return narrowQ.matches
        ? (video.dataset.srcNarrow || video.dataset.srcWide)
        : (video.dataset.srcWide || video.dataset.srcNarrow);
    }

    // STESSA logica per desktop e mobile: carica subito la sorgente (come il desktop che già
    // funziona — niente lazy-load, era l'unica differenza), abilita lo scrub appena nota la
    // durata, "prime" play→pause da muto così iOS/Safari dipinge i frame cercati.
    let loadedKey = "";
    function loadVideo() {
      if (!useVideo) return;
      const key = narrowQ.matches ? "narrow" : "wide";
      if (key === loadedKey) return; // già caricata la sorgente giusta
      loadedKey = key;
      duration = 0;
      video.preload = "auto";
      video.src = pickSrc();
      const prime = () => {
        duration = video.duration || 0;
        const pl = video.play();
        if (pl && pl.then) pl.then(() => video.pause()).catch(() => {});
        update();
      };
      video.addEventListener("loadedmetadata", prime, { once: true });
      // ri-applica il fotogramma corretto appena ci sono dati (su iOS il seek si dipinge qui)
      video.addEventListener("loadeddata", update, { once: true });
      video.addEventListener("canplay", update, { once: true });
      // fallback ai fotogrammi SOLO se la sorgente non carica davvero (errore reale)
      video.addEventListener("error", () => {
        videoMode = false;
        forge.classList.remove("is-video");
        forge.classList.add("is-stills");
        activeStill = -1;
        update();
      }, { once: true });
      video.load();
    }

    if (useVideo) {
      loadVideo();
      // al cambio breakpoint/orientamento ricarica la sorgente adatta
      const onBp = () => { if (loadedKey) { loadedKey = ""; loadVideo(); } };
      if (narrowQ.addEventListener) narrowQ.addEventListener("change", onBp);
      else if (narrowQ.addListener) narrowQ.addListener(onBp);
    }

    let forgeTick = false;
    function onForgeScroll() {
      if (!forgeTick) {
        forgeTick = true;
        requestAnimationFrame(() => { update(); forgeTick = false; });
      }
    }
    window.addEventListener("scroll", onForgeScroll, { passive: true });
    window.addEventListener("resize", onForgeScroll, { passive: true });
    update();

    // parallasse di profondità sul puntatore (desktop)
    if (media && !reduceMotion && matchMedia("(pointer: fine)").matches) {
      forge.addEventListener("pointermove", (e) => {
        const r = forge.getBoundingClientRect();
        const nx = (e.clientX - r.left) / r.width - 0.5;
        const ny = (e.clientY - r.top) / r.height - 0.5;
        media.style.setProperty("--px", (nx * 16).toFixed(1) + "px");
        media.style.setProperty("--py", (ny * 12).toFixed(1) + "px");
      }, { passive: true });
      forge.addEventListener("pointerleave", () => {
        media.style.setProperty("--px", "0px");
        media.style.setProperty("--py", "0px");
      });
    }
  }

  /* ---------- hero stat counters ---------- */
  const counters = [...document.querySelectorAll("[data-count]")];
  const counterObserver = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      const el = entry.target;
      const target = parseInt(el.dataset.count, 10);
      const dur = 1400;
      const t0 = performance.now();
      function tick(t) {
        const p = Math.min((t - t0) / dur, 1);
        const eased = 1 - Math.pow(1 - p, 3);
        el.textContent = Math.round(target * eased);
        if (p < 1) requestAnimationFrame(tick);
      }
      reduceMotion ? (el.textContent = target) : requestAnimationFrame(tick);
      counterObserver.unobserve(el);
    });
  }, { threshold: 0.6 });

  counters.forEach((el) => counterObserver.observe(el));

  /* ---------- demo lightbox modal ---------- */
  const modal = document.getElementById("demoModal");
  const stage = document.getElementById("modalStage");
  const modalTitle = document.getElementById("modalTitle");
  const modalDesc = document.getElementById("modalDesc");
  let lastFocused = null;

  function openDemo(card) {
    const scene = card.querySelector(".demo-scene");
    const title = card.querySelector(".demo-title");
    const desc = card.querySelector(".demo-desc");

    // clone restarts CSS animations in the modal
    stage.replaceChildren(scene.cloneNode(true));
    modalTitle.textContent = title.textContent;
    modalDesc.textContent = desc.textContent;

    lastFocused = document.activeElement;
    modal.hidden = false;
    document.body.classList.add("modal-open");
    modal.querySelector(".modal-close").focus();
  }

  function closeDemo() {
    modal.hidden = true;
    document.body.classList.remove("modal-open");
    stage.replaceChildren();
    if (lastFocused) lastFocused.focus();
  }

  document.querySelectorAll(".demo-card").forEach((card) => {
    card.addEventListener("click", () => openDemo(card));
    card.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        openDemo(card);
      }
    });
  });

  modal.querySelectorAll("[data-close]").forEach((el) =>
    el.addEventListener("click", closeDemo)
  );
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && !modal.hidden) closeDemo();
  });

  /* ---------- FAQ: close others when one opens ---------- */
  const faqItems = [...document.querySelectorAll(".faq-item")];
  faqItems.forEach((item) => {
    item.addEventListener("toggle", () => {
      if (item.open) faqItems.forEach((other) => { if (other !== item) other.open = false; });
    });
  });

  /* ---------- Chiron toggle: add supplement to every plan ---------- */
  const chironSwitch = document.getElementById("chironSwitch");
  const chironToggle = document.getElementById("chironToggle");
  if (chironSwitch && chironToggle) {
    const supplement = parseInt(chironSwitch.dataset.chironSupplement, 10) || 0;
    const cards = [...document.querySelectorAll(".price-card[data-base]")];

    const setChiron = (on) => {
      chironToggle.setAttribute("aria-checked", String(on));
      cards.forEach((card) => {
        const base = parseInt(card.dataset.base, 10);
        const numEl = card.querySelector("[data-price]");
        const chironLine = card.querySelector(".price-chiron");
        if (numEl) {
          numEl.classList.add("flip");
          setTimeout(() => {
            numEl.textContent = on ? base + supplement : base;
            numEl.classList.remove("flip");
          }, 130);
        }
        if (chironLine) chironLine.hidden = !on;
      });
    };

    chironToggle.addEventListener("click", () => {
      setChiron(chironToggle.getAttribute("aria-checked") !== "true");
    });
  }
})();
