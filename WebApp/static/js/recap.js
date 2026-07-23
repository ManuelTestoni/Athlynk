// recap.js — pagina "Genera recap atleta" (CHIRON).
// Chart instance FUORI dai dati reattivi Alpine (Proxy rompe Chart.js .update()
// — stesso motivo del pattern già in coach_progressi.js): qui non usiamo
// Chart.js ma un SVG disegnato a mano, quindi il nodo path stesso resta un
// riferimento DOM diretto, mai wrappato da Alpine.
document.addEventListener('alpine:init', () => {
  Alpine.data('coachRecap', () => ({
    loading: true,
    regenerating: false,
    error: null,
    payload: null,
    expanded: {},
    actionModal: { open: false, code: null, proposal: null, sending: false, resultMsg: null, resultError: false },
    feedbackGiven: {},
    settingsModal: { open: false, thresholds: {}, labels: {}, saving: false, savedMsg: '' },

    async init() {
      await this.load(false);
    },

    async load(force) {
      this.error = null;
      if (force) this.regenerating = true; else this.loading = true;
      try {
        const url = force ? this.urls.regenerate : this.urls.recap;
        const opts = force
          ? { method: 'POST', headers: { 'X-CSRFToken': window.csrfToken() } }
          : {};
        const r = await fetch(url, opts);
        if (!r.ok) throw new Error('http_' + r.status);
        this.payload = await r.json();
        this.$nextTick(() => this.renderTrajectory());
      } catch (e) {
        this.error = 'Non riesco a generare il recap in questo momento. Riprova tra poco.';
      } finally {
        this.loading = false;
        this.regenerating = false;
      }
    },

    toggle(code) {
      this.expanded[code] = !this.expanded[code];
    },

    // True quando il payload è arrivato ma non c'è nulla di utilizzabile:
    // niente peso affidabile, niente nei domini a cui QUESTO coach ha accesso
    // (sections_available — un coach WORKOUT-only non deve far scattare
    // questo stato solo perché non vede la nutrizione, che per lui non è
    // "dati mancanti" ma semplicemente fuori scope), zero insight, nessuna proiezione.
    isInsufficientData() {
      if (!this.payload) return false;
      const ds = this.payload.data_sufficiency || {};
      const scope = this.payload.sections_available || {};
      const anyReliable = ds.weight || (scope.training && ds.training) || (scope.nutrition && ds.nutrition);
      const hasInsights = (this.payload.insights || []).length > 0;
      const hasForecast = !!(this.payload.forecast && this.payload.forecast.available);
      return !anyReliable && !hasInsights && !hasForecast;
    },

    domainLabel(d) {
      return { body_comp: 'Corpo', nutrition: 'Nutrizione', training: 'Allenamento', cross: 'Quadro d\'insieme' }[d] || d;
    },

    directionLabel(dir) {
      return { up: 'In aumento', stable: 'Stabile', down: 'In calo' }[dir] || '—';
    },

    // Didascalia compatta di trend per le scorecard secondarie (vita,
    // aderenza nutrizionale) — forecast estesi V2, mai l'headline Direzione.
    trendCaption(forecast) {
      if (!forecast || !forecast.available) return '';
      const dirWord = { up: 'in aumento', stable: 'stabile', down: 'in calo' }[forecast.direction] || '';
      const confWord = { low: 'bassa', medium: 'media', high: 'alta' }[forecast.confidence] || '';
      return `Trend: ${dirWord} (confidenza ${confWord})`;
    },

    fmtNum(v, decimals) {
      if (v === null || v === undefined) return '—';
      return Number(v).toFixed(decimals === undefined ? 1 : decimals);
    },

    fmtSigned(v, decimals) {
      if (v === null || v === undefined) return '—';
      const n = Number(v);
      const s = n.toFixed(decimals === undefined ? 1 : decimals);
      return n > 0 ? '+' + s : s;
    },

    // Deep-link verso il widget chat globale (partials/chiron_widget.html):
    // precompila l'input, MAI invio automatico — il coach legge/modifica
    // prima di premere invio.
    askChiron(insight) {
      const name = this.clientName || 'questo atleta';
      const text = `Riguardo a ${name}: ${insight.observation} ${insight.interpretation} Cosa mi consigli di fare?`;
      if (window.openChironWithMessage) window.openChironWithMessage(text);
    },

    // V3 prep: cattura "utile/non utile" — nessuna calibrazione qui, solo
    // segnale per una futura pass su soglie/pesi delle regole.
    async giveFeedback(code, useful) {
      this.feedbackGiven[code] = useful; // ottimistico: reattivo subito
      try {
        await fetch(this.urls.insightFeedback, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': window.csrfToken() },
          body: JSON.stringify({ insight_code: code, useful }),
        });
      } catch (e) {
        // silenzioso: un feedback perso non deve disturbare la lettura del recap.
      }
    },

    // V3 prep: soglie di anomalia per-coach (CoachRecapSettings). Etichette
    // in italiano fisse lato client — le chiavi sono quelle di
    // insights.DEFAULT_THRESHOLDS, mai inventate qui.
    _thresholdLabels() {
      return {
        plateau_change_pct: "Calo carico/volume per plateau (%, negativo)",
        nutrition_weekend_gap_points: "Gap aderenza feriale/weekend (punti)",
        overreaching_rpe_delta: "Delta RPE per segnale di fatica",
        recomposition_weight_stable_kg: "Peso “stabile” entro ± (kg)",
        recomposition_waist_drop_cm: "Calo vita per ricomposizione (cm, negativo)",
      };
    },

    async openSettings() {
      this.settingsModal = { open: true, thresholds: {}, labels: this._thresholdLabels(), saving: false, savedMsg: '' };
      try {
        const r = await fetch(this.urls.recapSettings);
        const data = await r.json();
        this.settingsModal.thresholds = data.thresholds;
      } catch (e) {
        this.settingsModal.savedMsg = 'Non riesco a caricare le impostazioni.';
      }
    },

    closeSettings() {
      this.settingsModal.open = false;
    },

    async saveSettings() {
      this.settingsModal.saving = true;
      this.settingsModal.savedMsg = '';
      try {
        const r = await fetch(this.urls.recapSettings, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': window.csrfToken() },
          body: JSON.stringify({ thresholds: this.settingsModal.thresholds }),
        });
        if (!r.ok) throw new Error('http_' + r.status);
        this.settingsModal.savedMsg = 'Salvato — si applica dal prossimo recap generato.';
      } catch (e) {
        this.settingsModal.savedMsg = 'Salvataggio non riuscito.';
      } finally {
        this.settingsModal.saving = false;
      }
    },

    // --- Azioni consigliate: propose/confirm esistente (chiron/actions.py) ---
    async openActionModal(code) {
      this.actionModal = { open: true, code, proposal: null, sending: false, resultMsg: null, resultError: false };
      try {
        const r = await fetch(this.urls.insightAction, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': window.csrfToken() },
          body: JSON.stringify({ insight_code: code }),
        });
        const data = await r.json();
        if (!r.ok) throw new Error(data.error || 'errore');
        this.actionModal.proposal = data.proposal;
      } catch (e) {
        this.actionModal.resultError = true;
        this.actionModal.resultMsg = "Non riesco a preparare l'azione. Riprova.";
      }
    },

    closeActionModal() {
      this.actionModal.open = false;
    },

    async confirmAction() {
      if (!this.actionModal.proposal) return;
      this.actionModal.sending = true;
      try {
        const r = await fetch(this.urls.executeAction, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRFToken': window.csrfToken() },
          body: JSON.stringify(this.actionModal.proposal),
        });
        const data = await r.json();
        this.actionModal.resultError = !data.ok;
        this.actionModal.resultMsg = data.message || (data.ok ? 'Fatto.' : 'Azione non riuscita.');
        if (data.ok) setTimeout(() => this.closeActionModal(), 1600);
      } catch (e) {
        this.actionModal.resultError = true;
        this.actionModal.resultMsg = 'Azione non riuscita.';
      } finally {
        this.actionModal.sending = false;
      }
    },

    // --- Direzione: traiettoria peso storico + proiezione (segnale unico, §5 del piano) ---
    renderTrajectory() {
      const svg = document.getElementById('recapTrajectory');
      if (!svg) return;
      const sc = this.payload && this.payload.scorecards;
      const points = (sc && sc.weight_series) || [];
      svg.innerHTML = '';
      if (points.length < 2) return;

      const W = 600, H = 140, PAD = 14;
      const values = points.map(p => p.value);
      const forecast = this.payload.forecast;
      if (forecast && forecast.available) {
        values.push(forecast.projected_2w, forecast.projected_4w);
      }
      const min = Math.min(...values), max = Math.max(...values);
      const span = Math.max(max - min, 0.5);

      const nHist = points.length;
      const nTotal = nHist + (forecast && forecast.available ? 2 : 0);
      const xStep = (W - PAD * 2) / (nTotal - 1);
      const xAt = (i) => PAD + i * xStep;
      const yAt = (v) => H - PAD - ((v - min) / span) * (H - PAD * 2);

      const histPath = points.map((p, i) => (i === 0 ? 'M' : 'L') + xAt(i).toFixed(1) + ',' + yAt(p.value).toFixed(1)).join(' ');

      const ns = 'http://www.w3.org/2000/svg';
      const historyEl = document.createElementNS(ns, 'path');
      historyEl.setAttribute('d', histPath);
      historyEl.setAttribute('class', 'al-recap-line-path');
      svg.appendChild(historyEl);

      const lastPt = { x: xAt(nHist - 1), y: yAt(points[nHist - 1].value) };
      const dotEl = document.createElementNS(ns, 'circle');
      dotEl.setAttribute('cx', lastPt.x); dotEl.setAttribute('cy', lastPt.y); dotEl.setAttribute('r', 3.5);
      dotEl.setAttribute('class', 'al-recap-line-dot');
      svg.appendChild(dotEl);

      let forecastEl = null;
      if (forecast && forecast.available) {
        const p2 = { x: xAt(nHist), y: yAt(forecast.projected_2w) };
        const p4 = { x: xAt(nHist + 1), y: yAt(forecast.projected_4w) };
        // Banda di confidenza qualitativa: solo la larghezza cambia (bassa=larga,
        // alta=stretta) — mai un vero intervallo statistico, §5 del piano.
        // Floor a 6 anche per "alta": sotto quella soglia la banda diventa
        // invisibile a schermo e perde il suo scopo di comunicare l'incertezza.
        const bandHalf = { low: 20, medium: 13, high: 6 }[forecast.confidence] || 13;
        const band = document.createElementNS(ns, 'path');
        band.setAttribute('d',
          `M${lastPt.x},${lastPt.y - bandHalf * 0.3} L${p2.x},${p2.y - bandHalf * 0.65} L${p4.x},${p4.y - bandHalf} ` +
          `L${p4.x},${p4.y + bandHalf} L${p2.x},${p2.y + bandHalf * 0.65} L${lastPt.x},${lastPt.y + bandHalf * 0.3} Z`);
        band.setAttribute('class', 'al-recap-line-band');
        svg.appendChild(band);

        forecastEl = document.createElementNS(ns, 'path');
        forecastEl.setAttribute('d', `M${lastPt.x},${lastPt.y} L${p2.x},${p2.y} L${p4.x},${p4.y}`);
        forecastEl.setAttribute('class', 'al-recap-line-forecast');
        svg.appendChild(forecastEl);
      }

      const reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

      // Storico: "disegnato" via stroke-dashoffset (richiede sovrascrivere
      // dasharray con [length,length] — per questo NON si applica al tratto
      // di forecast, che ha un dasharray fisso 5-5 da CSS per leggersi come
      // "proiezione" e non come dato reale).
      if (historyEl && !reduceMotion) {
        const len = historyEl.getTotalLength();
        historyEl.dataset.draw = '';
        historyEl.style.strokeDasharray = len + ' ' + len;
        historyEl.style.strokeDashoffset = len;
        historyEl.getBoundingClientRect(); // forza reflow prima di animare
        requestAnimationFrame(() => { historyEl.style.strokeDashoffset = '0'; });
      }

      // Forecast: fade-in (mai un dash-offset draw, altrimenti il dasharray
      // 5-5 verrebbe sovrascritto e il tratto sparirebbe visivamente dentro
      // lo storico) — coerente anche col significato ("meno certo" = appare
      // gradualmente, non si "traccia" come un fatto).
      if (forecastEl) {
        if (reduceMotion) {
          forecastEl.style.opacity = '1';
        } else {
          forecastEl.style.opacity = '0';
          forecastEl.style.transition = 'opacity var(--al-d-slow, .6s) ease-out';
          forecastEl.getBoundingClientRect();
          requestAnimationFrame(() => { forecastEl.style.opacity = '1'; });
        }
      }
    },
  }));
});
