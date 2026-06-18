// Stop mouse-wheel / trackpad scroll from changing the value of a focused
// number input. Browsers increment/decrement <input type="number"> on wheel
// while it has focus, so a stray two-finger scroll silently edits quantities.
// We cancel the wheel only when the focused element is the one being scrolled —
// page scrolling and keyboard/spinner editing keep working.
(function () {
  'use strict';
  document.addEventListener('wheel', function (e) {
    var el = document.activeElement;
    if (el && el.tagName === 'INPUT' && el.type === 'number' &&
        (el === e.target || el.contains(e.target))) {
      e.preventDefault();
    }
  }, { passive: false });
})();
