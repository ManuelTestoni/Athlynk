/* Athlynk date/time pickers — auto-attach Flatpickr to all native inputs.
   - type="date"           → date picker, ISO yyyy-mm-dd
   - type="datetime-local" → date + 24h time, ISO yyyy-mm-ddTHH:MM
   - type="time"           → time only, 24h
   Observes the DOM so dynamically-added inputs (Alpine modals) get
   wired up automatically. Paired start/end inputs whose names match
   *start_datetime / *end_datetime (or data-fp-pair-start / -end) get
   end >= start enforcement live.
*/

(function () {
  if (typeof flatpickr === 'undefined') return;

  if (window.flatpickr && window.flatpickr.l10ns && window.flatpickr.l10ns.it) {
    flatpickr.localize(flatpickr.l10ns.it);
  }

  const COMMON = {
    allowInput: true,
    disableMobile: true,
    monthSelectorType: 'static',
    locale: (window.flatpickr && window.flatpickr.l10ns && window.flatpickr.l10ns.it) || undefined,
  };

  function configFor(input) {
    const t = (input.getAttribute('type') || '').toLowerCase();
    if (t === 'datetime-local') {
      return Object.assign({}, COMMON, {
        enableTime: true,
        time_24hr: true,
        dateFormat: 'Y-m-d\\TH:i',
        minuteIncrement: 5,
      });
    }
    if (t === 'time') {
      return Object.assign({}, COMMON, {
        enableTime: true,
        noCalendar: true,
        time_24hr: true,
        dateFormat: 'H:i',
        minuteIncrement: 5,
      });
    }
    return Object.assign({}, COMMON, {
      dateFormat: 'Y-m-d',
      altInput: false,
    });
  }

  function attach(input) {
    if (!input || input._fp || input.dataset.fpSkip === 'true') return;
    if (input.closest('[data-fp-skip]')) return;
    const inst = flatpickr(input, configFor(input));
    input._fp = inst;
  }

  function findPair(input) {
    const name = input.getAttribute('name') || input.getAttribute('x-model') || '';
    const form = input.form || input.closest('form, [x-data], .al-modal-panel, body');
    if (!form) return null;
    if (input.dataset.fpPairEnd) {
      const sel = input.dataset.fpPairEnd;
      return form.querySelector(sel);
    }
    if (/start_datetime\b/.test(name) || /start_date\b/.test(name)) {
      const target = name.replace('start_', 'end_');
      return form.querySelector(
        `[name="${target}"], [x-model="${target}"], [x-model$=".${target}"]`
      );
    }
    return null;
  }

  function wirePairing() {
    document.querySelectorAll('input').forEach((input) => {
      if (!input._fp || input._fpPairWired) return;
      const partner = findPair(input);
      if (!partner) return;
      input._fpPairWired = true;
      const sync = () => {
        if (!partner._fp || !input._fp) return;
        const startDate = input._fp.selectedDates[0];
        if (!startDate) return;
        partner._fp.set('minDate', startDate);
        const endDate = partner._fp.selectedDates[0];
        if (endDate && endDate < startDate) {
          partner._fp.setDate(startDate, true);
        }
      };
      input._fp.config.onChange.push(sync);
      sync();
    });
  }

  function scan(root) {
    const scope = root && root.querySelectorAll ? root : document;
    scope.querySelectorAll(
      'input[type="date"], input[type="datetime-local"], input[type="time"]'
    ).forEach(attach);
    wirePairing();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => scan(document));
  } else {
    scan(document);
  }

  // Watch for dynamically inserted inputs (Alpine modals etc.)
  const obs = new MutationObserver((mutations) => {
    let needsScan = false;
    for (const m of mutations) {
      for (const n of m.addedNodes) {
        if (n.nodeType !== 1) continue;
        if (n.matches && n.matches('input[type="date"], input[type="datetime-local"], input[type="time"]')) {
          needsScan = true;
          break;
        }
        if (n.querySelector && n.querySelector('input[type="date"], input[type="datetime-local"], input[type="time"]')) {
          needsScan = true;
          break;
        }
      }
      if (needsScan) break;
    }
    if (needsScan) scan(document);
  });
  obs.observe(document.body, { childList: true, subtree: true });

  window.AthlynkPickers = { attach, scan };
})();
