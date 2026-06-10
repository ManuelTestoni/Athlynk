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
  const sections = ["hero", "chiron", "pricing", "about", "faq"]
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
})();
