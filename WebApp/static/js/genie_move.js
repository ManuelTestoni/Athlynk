/* Athlynk — shared "fly to target" drag-drop animation.
   Usage: await window.alGenieMove(sourceEl, targetEl)
   Clones sourceEl, flies+shrinks it toward targetEl's center, then removes it.
   Used when a dragged card is dropped on a folder, before the source list re-renders. */
window.alGenieMove = function alGenieMove(sourceEl, targetEl, opts = {}) {
  if (!sourceEl || !targetEl) return Promise.resolve();
  const duration = opts.duration || 500;
  const srcRect = sourceEl.getBoundingClientRect();
  const tgtRect = targetEl.getBoundingClientRect();
  if (!srcRect.width || !srcRect.height) return Promise.resolve();

  const clone = sourceEl.cloneNode(true);
  Object.assign(clone.style, {
    position: 'fixed',
    left: srcRect.left + 'px',
    top: srcRect.top + 'px',
    width: srcRect.width + 'px',
    height: srcRect.height + 'px',
    margin: '0',
    zIndex: '9999',
    pointerEvents: 'none',
    transformOrigin: 'center center',
    transition: `transform ${duration}ms var(--al-ease-out, cubic-bezier(.16,1,.3,1)), opacity ${duration}ms var(--al-ease-out, cubic-bezier(.16,1,.3,1))`,
  });
  document.body.appendChild(clone);

  const dx = (tgtRect.left + tgtRect.width / 2) - (srcRect.left + srcRect.width / 2);
  const dy = (tgtRect.top + tgtRect.height / 2) - (srcRect.top + srcRect.height / 2);

  return new Promise((resolve) => {
    const done = () => { clone.remove(); resolve(); };
    requestAnimationFrame(() => requestAnimationFrame(() => {
      clone.style.transform = `translate(${dx}px, ${dy}px) scale(0.15)`;
      clone.style.opacity = '0';
    }));
    clone.addEventListener('transitionend', done, { once: true });
    setTimeout(done, duration + 80); // fallback in case transitionend never fires
  });
};
