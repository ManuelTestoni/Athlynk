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
     EXPLORER — perspective + feature picker
     .explorer > .explorer-menu (.explorer-tab[data-view]*, .explorer-list
       [data-view-panel]* > .explorer-item[data-asset-count]* + .explorer-indicator)
     .explorer > .explorer-stage (frame[data-view-panel]* > .reel-frame >
       .reel-slide* + .reel-nav(.reel-prev/.reel-next/.reel-count) ,
       .explorer-caption)
     Nothing plays on its own — the visitor picks a perspective and a
     feature, the stage crossfades to match, a gold rule slides to the
     active row. A feature can own more than one asset (data-asset-count on the
     .explorer-item) — the reel-nav arrows then cycle within that feature's
     own slides only, wrapping both ways, without changing which feature
     is selected.
     ============================================================ */
  document.querySelectorAll(".explorer").forEach((explorer) => {
    const tabs = [...explorer.querySelectorAll(".explorer-tab")];
    const lists = [...explorer.querySelectorAll(".explorer-list")];
    const frames = [...explorer.querySelectorAll(".explorer-stage [data-view-panel]")];
    const caption = explorer.querySelector(".explorer-caption");
    if (!tabs.length || !lists.length) return;

    function placeIndicator(list) {
      const indicator = list.querySelector(".explorer-indicator");
      const active = list.querySelector(".explorer-item.is-active");
      if (!indicator || !active) return;
      indicator.style.transform = `translateY(${active.offsetTop}px)`;
      indicator.style.height = `${active.offsetHeight}px`;
    }

    function frameFor(view) {
      return frames.find((f) => f.dataset.viewPanel === view);
    }

    function renderSlide(frame, slideIndex) {
      const slides = [...frame.querySelectorAll(".reel-slide")];
      slides.forEach((s, k) => s.classList.toggle("is-active", k === slideIndex));
      const active = slides[slideIndex];
      if (caption) caption.textContent = (active && active.dataset.label) || "";
      const urlEl = frame.querySelector(".browser-url");
      if (urlEl && active && active.dataset.url) urlEl.textContent = active.dataset.url;
      const count = parseInt(frame.dataset.groupCount || "1", 10);
      const offset = parseInt(frame.dataset.groupOffset || "0", 10);
      const nav = frame.querySelector(".reel-nav");
      if (nav) {
        nav.hidden = count <= 1;
        const counter = nav.querySelector(".reel-count");
        if (counter) counter.textContent = count > 1 ? `${offset + 1} / ${count}` : "";
      }
    }

    function activateItem(list, index) {
      const items = [...list.querySelectorAll(".explorer-item")];
      const frame = frameFor(list.dataset.viewPanel);
      items.forEach((it, k) => it.classList.toggle("is-active", k === index));
      placeIndicator(list);
      if (!frame) return;
      let start = 0;
      items.forEach((it, k) => { if (k < index) start += parseInt(it.dataset.assetCount || "1", 10); });
      frame.dataset.groupStart = start;
      frame.dataset.groupCount = parseInt(items[index]?.dataset.assetCount || "1", 10);
      frame.dataset.groupOffset = 0;
      renderSlide(frame, start);
    }

    lists.forEach((list) => {
      const items = [...list.querySelectorAll(".explorer-item")];
      items.forEach((item, i) => item.addEventListener("click", () => activateItem(list, i)));
    });

    frames.forEach((frame) => {
      const nav = frame.querySelector(".reel-nav");
      if (!nav) return;
      const step = (delta) => {
        const start = parseInt(frame.dataset.groupStart || "0", 10);
        const count = parseInt(frame.dataset.groupCount || "1", 10);
        const offset = (parseInt(frame.dataset.groupOffset || "0", 10) + delta + count) % count;
        frame.dataset.groupOffset = offset;
        renderSlide(frame, start + offset);
      };
      nav.querySelector(".reel-prev")?.addEventListener("click", () => step(-1));
      nav.querySelector(".reel-next")?.addEventListener("click", () => step(1));
    });

    function activateView(view) {
      tabs.forEach((t) => {
        const on = t.dataset.view === view;
        t.classList.toggle("is-active", on);
        t.setAttribute("aria-selected", on ? "true" : "false");
      });
      lists.forEach((l) => { l.hidden = l.dataset.viewPanel !== view; });
      frames.forEach((f) => { f.hidden = f.dataset.viewPanel !== view; });
      const list = lists.find((l) => l.dataset.viewPanel === view);
      if (list) activateItem(list, 0);
    }

    tabs.forEach((t) => t.addEventListener("click", () => activateView(t.dataset.view)));

    const initialList = lists.find((l) => !l.hidden) || lists[0];
    activateItem(initialList, 0);
    window.addEventListener("resize", () => {
      const visible = lists.find((l) => !l.hidden);
      if (visible) placeIndicator(visible);
    });
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

  /* ============================================================
     CHIRON — mini-demo interattiva
     Mascotte cliccabile → si apre chat + testo; l'utente sceglie un
     argomento, Chiron "pensa" (puntini) e risponde. Rieleggibile.
     ============================================================ */
  (() => {
    const stage = document.getElementById("chironStage");
    const mascot = document.getElementById("chironMascot");
    const layout = document.getElementById("chironLayout");
    const log = document.getElementById("chironLog");
    const optionsWrap = document.getElementById("chironOptions");
    if (!stage || !mascot || !layout || !log || !optionsWrap) return;

    const GREETING = "Ciao, sono <b>CHIRON</b>. Posso aiutarti su allenamenti, nutrizione e gestione atleti. Chiedi pure.";

    const TOPICS = {
      allenamento: {
        label: "Allenamento",
        html: `Posso aiutarti in tutti gli aspetti dell'allenamento:
          <ul>
            <li><b>Programmazione e periodizzazione</b>: creazione di macro-, meso- e micro-cicli, adattamento a obiettivi specifici (forza, potenza, resistenza, perdita di grasso, performance sportiva).</li>
            <li><b>Pianificazione individualizzata</b>: analisi delle capacità, dei punti di forza e delle debolezze per costruire un programma su misura.</li>
            <li><b>Tecnica e biomeccanica</b>: consigli su esecuzione corretta, prevenzione infortuni, ottimizzazione del movimento.</li>
            <li><b>Progressione e carichi</b>: indicazioni su come aumentare volume, intensità e frequenza in modo sicuro.</li>
            <li><b>Recupero e nutrizione</b>: integrazione di strategie di recupero (sleep, stretching, foam-rolling) e di supporto nutrizionale per massimizzare i risultati.</li>
            <li><b>Monitoraggio e feedback</b>: interpretazione dei check, analisi dei dati di performance e suggerimenti per aggiustamenti in tempo reale.</li>
          </ul>`,
      },
      nutrizione: {
        label: "Nutrizione",
        html: `Per la nutrizione posso aiutarti con:
          <ul>
            <li><b>Pianificazione alimentare personalizzata</b> (macro- e micro-nutrienti, calorie, timing dei pasti).</li>
            <li><b>Calcolo dei fabbisogni energetici</b> in base a obiettivi (guadagno muscolare, perdita grasso, mantenimento).</li>
            <li><b>Creazione di menu settimanali</b> con ricette, sostituzioni e consigli pratici.</li>
            <li><b>Gestione di restrizioni dietetiche</b> (celiachia, intolleranze, veganesimo, ecc.).</li>
            <li><b>Supporto per integrazione</b> (proteine, aminoacidi, vitamine, minerali).</li>
            <li><b>Monitoraggio e analisi dei check nutrizionali</b>: confronto con obiettivi, suggerimenti di aggiustamento.</li>
            <li><b>Consulenza su periodizzazione nutrizionale</b> (carb-cycling, refeed, fasting).</li>
            <li><b>Educazione nutrizionale</b>: spiegazione di principi di bilancio energetico e micronutrienti essenziali.</li>
          </ul>`,
      },
      gestione: {
        label: "Gestione atleti",
        html: `Posso aiutarti a gestire i tuoi atleti in modo completo:
          <table>
            <thead><tr><th>Area</th><th>Come aiuto</th></tr></thead>
            <tbody>
              <tr><td>Dashboard e report</td><td>Snapshot rapidi su check, sessioni, peso, infortuni.</td></tr>
              <tr><td>Pianificazione</td><td>Macro-, meso- e micro-cicli personalizzati.</td></tr>
              <tr><td>Monitoraggio</td><td>Analisi dei check, progressi, aree di miglioramento.</td></tr>
              <tr><td>Comunicazione</td><td>Messaggi in chat, feedback automatici, check revisionati.</td></tr>
              <tr><td>Follow-up</td><td>Atleti a rischio abbandono, promemoria mirati.</td></tr>
              <tr><td>Integrazione</td><td>Suggerimenti basati sui check dell'atleta.</td></tr>
              <tr><td>Report periodici</td><td>Report settimanali o mensili per ogni atleta.</td></tr>
              <tr><td>Automazione</td><td>Azioni proposte da confermare con un tocco.</td></tr>
            </tbody>
          </table>`,
      },
    };

    function scrollToBottom() { log.scrollTop = log.scrollHeight; }

    function addAiMessage(html) {
      const el = document.createElement("div");
      el.className = "app-msg app-msg-ai";
      el.innerHTML = `<span class="app-msg-av" aria-hidden="true">✦</span><span class="app-msg-body">${html}</span>`;
      log.appendChild(el);
      scrollToBottom();
    }

    function addUserMessage(text) {
      const el = document.createElement("div");
      el.className = "app-msg app-msg-coach";
      el.innerHTML = `<span class="app-msg-av" aria-hidden="true">TU</span><span class="app-msg-body">${text}</span>`;
      log.appendChild(el);
      scrollToBottom();
    }

    function addTyping() {
      const el = document.createElement("div");
      el.className = "app-msg app-msg-ai";
      el.innerHTML = '<span class="app-msg-av" aria-hidden="true">✦</span><span class="app-typing" aria-hidden="true"><i style="--d:0s"></i><i style="--d:0.2s"></i><i style="--d:0.4s"></i></span>';
      log.appendChild(el);
      scrollToBottom();
      return el;
    }

    mascot.addEventListener("click", () => {
      mascot.classList.add("is-hidden");
      setTimeout(() => { mascot.hidden = true; }, 400);
      layout.hidden = false;
      void layout.offsetWidth; // force reflow so the slide-in transition runs
      stage.classList.add("is-active");
      addAiMessage(GREETING);
    }, { once: true });

    const optionButtons = [...optionsWrap.querySelectorAll("[data-topic]")];
    let busy = false;
    optionButtons.forEach((btn) => {
      btn.addEventListener("click", () => {
        if (busy) return;
        const topic = TOPICS[btn.dataset.topic];
        if (!topic) return;
        busy = true;
        optionButtons.forEach((b) => b.classList.toggle("is-active", b === btn));
        addUserMessage(topic.label);
        const typingEl = addTyping();
        setTimeout(() => {
          typingEl.remove();
          addAiMessage(topic.html);
          busy = false;
        }, 950);
      });
    });
  })();
})();
