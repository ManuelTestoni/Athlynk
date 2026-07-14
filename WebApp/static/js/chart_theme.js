// Shared Chart.js defaults: one gold-bordered external tooltip for every
// chart in the app, rendered as a real DOM node appended to <body> (not a
// descendant of the chart's card). A canvas-drawn tooltip has no z-index of
// its own, so it always loses to sibling overlays inside the same stacking
// context (e.g. the fixed .pc-yaxis band on the check charts). Appending to
// <body> escapes that context entirely.
(function () {
  if (typeof Chart === 'undefined') return;

  const els = new Map();

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
  }

  function getTooltipEl(chart) {
    let el = els.get(chart.id);
    if (!el) {
      el = document.createElement('div');
      el.className = 'al-chart-tooltip';
      document.body.appendChild(el);
      els.set(chart.id, el);
    }
    return el;
  }

  function externalTooltip(context) {
    const { chart, tooltip } = context;
    const el = getTooltipEl(chart);

    if (tooltip.opacity === 0) {
      el.style.opacity = '0';
      return;
    }

    if (tooltip.body) {
      let html = '';
      (tooltip.title || []).forEach((t) => {
        html += '<div class="al-chart-tooltip-title">' + escapeHtml(t) + '</div>';
      });
      tooltip.body.forEach((b) => {
        b.lines.forEach((line) => {
          html += '<div class="al-chart-tooltip-line">' + escapeHtml(line) + '</div>';
        });
      });
      el.innerHTML = html;
    }

    const rect = chart.canvas.getBoundingClientRect();
    el.style.opacity = '1';
    el.style.left = (rect.left + tooltip.caretX) + 'px';
    el.style.top = (rect.top + tooltip.caretY) + 'px';
  }

  Chart.register({
    id: 'alTooltipCleanup',
    afterDestroy(chart) {
      const el = els.get(chart.id);
      if (el) {
        el.remove();
        els.delete(chart.id);
      }
    },
  });

  Chart.defaults.plugins.tooltip.enabled = false;
  Chart.defaults.plugins.tooltip.external = externalTooltip;
})();
