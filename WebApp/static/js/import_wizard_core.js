// Generic import wizard primitives shared by AI-import features (diet, workout).
//
// Exposes window.createImportWizardCore(config) → returns an Alpine-compatible
// object with the following responsibilities:
//   • step machine (1=upload, 2=loading, 3=review, 'error')
//   • file drop / pick / validation (extPattern, maxBytes)
//   • client picker (uses /api/clients/search/)
//   • loading-step animation with phase gating + motivational messages
//   • sync POST + async POST + status polling
//   • error code → human label translation
//
// The factory does NOT know about domain models. Callers add domain-specific
// state (diet/workout JSON), hydrate(), save(), and chart adapters via
// Object.assign() on top.

(function () {
  'use strict';

  const DEFAULTS = {
    sourceType: 'excel',
    accept: '.xlsx,.xls',
    extPattern: /\.(xlsx|xls)$/i,
    maxBytes: 10 * 1024 * 1024,
    submitUrl: '',
    statusUrl: null,
    confirmUrl: '',
    async: false,
    pollIntervalMs: 1500,
    showSourceBadge: false,
    minPerceivedMs: 4500,
    phaseMap: null,
    minPhaseMs: null,
    steps: [],
    motivationalMessages: ['Sto elaborando...'],
    copy: {
      formatError: 'Formato non supportato',
      tooLargeError: 'File troppo grande',
      invalidFileError: 'File non leggibile.',
    },
    clientSearchUrl: '/api/clients/search/',
  };

  function createImportWizardCore(userConfig) {
    const cfg = Object.assign({}, DEFAULTS, userConfig || {});
    cfg.copy = Object.assign({}, DEFAULTS.copy, (userConfig && userConfig.copy) || {});

    return {
      cfg,
      currentStep: 1,

      // Step 1
      file: null,
      dragOver: false,
      clientSearch: '',
      selectedClient: null,
      clientDropdownOpen: false,
      clientResults: [],
      planTitle: '',

      // Step 2
      steps: cfg.steps.slice(),
      motivationalMessages: cfg.motivationalMessages.slice(),
      motivationalMsg: '',
      motivationalTimer: null,
      phase: 0,
      phaseTimer: null,
      gateTimer: null,
      targetPhase: 0,
      displayedPhase: 0,
      phaseEnteredAt: [],
      pollTimer: null,
      pollProgressPercent: 0,
      jobId: null,
      pendingResult: null,

      // Misc
      errorMsg: '',
      toast: '',
      toastTimer: null,
      saving: false,
      csrf: '',

      _initCore() {
        const meta = document.querySelector('meta[name="csrf-token"]');
        this.csrf = meta ? meta.content : '';
        this.searchClients();
      },

      get canSubmit() {
        return this.file && this.selectedClient && this.planTitle.trim().length > 0;
      },

      get filteredClients() { return this.clientResults; },

      formatSize(bytes) {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
        return (bytes / 1024 / 1024).toFixed(2) + ' MB';
      },

      async searchClients() {
        const q = this.clientSearch || '';
        try {
          const r = await fetch(this.cfg.clientSearchUrl + '?q=' + encodeURIComponent(q));
          if (r.ok) this.clientResults = await r.json();
        } catch (e) { console.error(e); }
      },

      pickClient(c) {
        this.selectedClient = c;
        this.clientSearch = c.name;
        this.clientDropdownOpen = false;
      },

      onFile(ev) {
        const f = ev.target.files && ev.target.files[0];
        if (f) this.setFile(f);
      },

      onDrop(ev) {
        this.dragOver = false;
        const f = ev.dataTransfer && ev.dataTransfer.files && ev.dataTransfer.files[0];
        if (f) this.setFile(f);
      },

      setFile(f) {
        const name = (f.name || '').toLowerCase();
        if (!this.cfg.extPattern.test(name)) {
          this.flashError(this.cfg.copy.formatError);
          return;
        }
        if (f.size > this.cfg.maxBytes) {
          this.flashError(this.cfg.copy.tooLargeError);
          return;
        }
        this.file = f;
      },

      clearFile() {
        this.file = null;
        if (this.$refs && this.$refs.fileInput) this.$refs.fileInput.value = '';
      },

      flashError(msg) {
        this.errorMsg = msg;
        this.currentStep = 'error';
      },

      flashToast(msg) {
        this.toast = msg;
        if (this.toastTimer) clearTimeout(this.toastTimer);
        this.toastTimer = setTimeout(() => { this.toast = ''; }, 3000);
      },

      // ─── Submit + loading anim ─────────────────────────────────
      async submitFile() {
        if (!this.canSubmit) return;
        this.currentStep = 2;
        this.startLoadingAnim();
        const fd = new FormData();
        fd.append('file', this.file);
        fd.append('plan_title', this.planTitle);
        fd.append('client_id', this.selectedClient.id);
        if (this.cfg.async) await this.submitAsync(fd);
        else await this.submitSync(fd);
      },

      async submitSync(fd) {
        const minDelay = new Promise(res => setTimeout(res, this.cfg.minPerceivedMs));
        try {
          const [resp] = await Promise.all([
            fetch(this.cfg.submitUrl, { method: 'POST', headers: { 'X-CSRFToken': this.csrf }, body: fd }),
            minDelay,
          ]);
          this.stopLoadingAnim();
          if (!resp.ok && resp.status !== 206) {
            const err = await resp.json().catch(() => ({}));
            this.errorMsg = this.translateError(err);
            this.currentStep = 'error';
            return;
          }
          const data = await resp.json();
          this.applyExtractionResult(data);
        } catch (e) {
          this.stopLoadingAnim();
          this.errorMsg = 'Errore di rete: ' + (e.message || e);
          this.currentStep = 'error';
        }
      },

      async submitAsync(fd) {
        try {
          const startResp = await fetch(this.cfg.submitUrl, {
            method: 'POST', headers: { 'X-CSRFToken': this.csrf }, body: fd,
          });
          if (!startResp.ok) {
            this.stopLoadingAnim();
            const err = await startResp.json().catch(() => ({}));
            this.errorMsg = this.translateError(err);
            this.currentStep = 'error';
            return;
          }
          const startData = await startResp.json();
          this.jobId = startData.job_id;
          if (!this.jobId) {
            this.stopLoadingAnim();
            this.errorMsg = 'Avvio elaborazione fallito (nessun job_id)';
            this.currentStep = 'error';
            return;
          }
          this.startPolling();
        } catch (e) {
          this.stopLoadingAnim();
          this.errorMsg = 'Errore di rete: ' + (e.message || e);
          this.currentStep = 'error';
        }
      },

      startPolling() {
        if (this.pollTimer) clearInterval(this.pollTimer);
        this.pollTimer = setInterval(() => this.pollOnce(), this.cfg.pollIntervalMs);
        this.pollOnce();
      },

      stopPolling() {
        if (this.pollTimer) { clearInterval(this.pollTimer); this.pollTimer = null; }
      },

      async pollOnce() {
        if (!this.jobId) return;
        try {
          const r = await fetch(this.cfg.statusUrl + '?job_id=' + encodeURIComponent(this.jobId));
          if (!r.ok) {
            this.stopPolling(); this.stopLoadingAnim();
            const err = await r.json().catch(() => ({}));
            this.errorMsg = this.translateError(err);
            this.currentStep = 'error';
            return;
          }
          const data = await r.json();
          this.pollProgressPercent = data.percent || 0;
          if (data.phase && this.cfg.phaseMap && this.cfg.phaseMap[data.phase] != null) {
            const next = this.cfg.phaseMap[data.phase];
            if (this.cfg.minPhaseMs) {
              if (next > this.targetPhase) this.targetPhase = next;
            } else {
              this.phase = next;
            }
          }
          if (data.status === 'done') {
            this.stopPolling();
            if (this.cfg.minPhaseMs) {
              this.targetPhase = this.steps.length - 1;
              this.pendingResult = data.result || {};
            } else {
              this.stopLoadingAnim();
              this.applyExtractionResult(data.result || {});
            }
          } else if (data.status === 'error') {
            this.stopPolling(); this.stopLoadingAnim();
            this.errorMsg = this.translateError({ error: data.error_code, detail: data.detail });
            this.currentStep = 'error';
          }
        } catch (e) {
          console.warn('poll error', e);
        }
      },

      tickPhaseGate() {
        const mins = this.cfg.minPhaseMs || [];
        if (!mins.length) return;
        const now = Date.now();
        while (this.displayedPhase < this.targetPhase) {
          const min = mins[this.displayedPhase] || 0;
          const enteredAt = this.phaseEnteredAt[this.displayedPhase] || now;
          if (now - enteredAt < min) break;
          this.displayedPhase++;
          this.phaseEnteredAt[this.displayedPhase] = now;
        }
        this.phase = this.displayedPhase;
        if (this.pendingResult && this.displayedPhase >= this.steps.length - 1) {
          const lastMin = mins[this.displayedPhase] || 0;
          const enteredAt = this.phaseEnteredAt[this.displayedPhase] || now;
          if (now - enteredAt >= lastMin) {
            const result = this.pendingResult;
            this.pendingResult = null;
            this.stopLoadingAnim();
            this.applyExtractionResult(result);
          }
        }
      },

      startLoadingAnim() {
        this.phase = 0;
        this.targetPhase = 0;
        this.displayedPhase = 0;
        this.phaseEnteredAt = [Date.now()];
        this.pendingResult = null;
        this.pollProgressPercent = 0;
        let i = 0;
        this.motivationalMsg = this.motivationalMessages[0];
        if (!this.cfg.async) {
          this.phaseTimer = setInterval(() => {
            if (this.phase < this.steps.length - 1) this.phase++;
          }, 1500);
        }
        if (this.cfg.async && this.cfg.minPhaseMs) {
          this.gateTimer = setInterval(() => this.tickPhaseGate(), 250);
        }
        this.motivationalTimer = setInterval(() => {
          i = (i + 1) % this.motivationalMessages.length;
          this.motivationalMsg = this.motivationalMessages[i];
        }, 2000);
      },

      stopLoadingAnim() {
        if (this.phaseTimer) { clearInterval(this.phaseTimer); this.phaseTimer = null; }
        if (this.gateTimer) { clearInterval(this.gateTimer); this.gateTimer = null; }
        if (this.motivationalTimer) { clearInterval(this.motivationalTimer); this.motivationalTimer = null; }
        this.phase = this.steps.length;
      },

      translateError(err) {
        if (!err) return 'Estrazione fallita.';
        const code = err.error;
        const map = {
          excel_invalid: 'Il file Excel non è leggibile. Prova con un altro formato.',
          pdf_invalid: 'Non siamo riusciti a leggere questo PDF. Prova con un file diverso.',
          pdf_no_content: 'Il documento non sembra contenere una scheda riconoscibile.',
          ai_failed: 'L\'analisi AI non è riuscita. Riprova tra poco.',
          job_not_found: 'Sessione di elaborazione scaduta. Riprova.',
          unknown: 'Errore inatteso durante l\'estrazione.',
          unmatched_exercises: 'Risolvi tutti gli esercizi prima di salvare.',
          save_failed: 'Salvataggio fallito.',
        };
        return map[code] || err.detail || err.error || 'Estrazione fallita.';
      },

      // Subclasses override applyExtractionResult to hydrate domain state.
      applyExtractionResult(data) {
        this.currentStep = 3;
      },
    };
  }

  window.createImportWizardCore = createImportWizardCore;
})();
