// Config Alpine per import dieta da PDF. Riusa createDietImporter() (diet_importer.js).
// Differenze rispetto a Excel:
//   - 5 step di loading (mappati alle fasi backend via phaseMap)
//   - submit async con polling sullo status endpoint
//   - max 20MB, accept .pdf
//   - badge "Pag. N" sui food nella review

function dietImporterPdf() {
  return window.createDietImporter({
    sourceType: 'pdf',
    accept: '.pdf',
    extPattern: /\.pdf$/i,
    maxBytes: 20 * 1024 * 1024,
    submitUrl: '/api/nutrizione/import/pdf/',
    statusUrl: '/api/nutrizione/import/pdf/status/',
    async: true,
    pollIntervalMs: 1500,
    showSourceBadge: true,
    steps: [
      { icon: 'ph ph-file-pdf', label: 'Analisi del PDF...' },
      { icon: 'ph ph-magnifying-glass', label: 'Identificazione pagine rilevanti...' },
      { icon: 'ph ph-scan', label: 'OCR delle pagine necessarie...' },
      { icon: 'ph ph-brain', label: 'Estrazione AI della dieta...' },
      { icon: 'ph ph-list-checks', label: 'Preparazione revisione finale...' },
    ],
    motivationalMessages: [
      'Sto leggendo il documento pagina per pagina...',
      'Sto identificando le sezioni dieta...',
      'Sto leggendo le pagine scansionate...',
      'Sto estraendo alimenti e quantità...',
      'Sto unendo i giorni della settimana...',
    ],
    phaseMap: {
      analyze: 0,
      classify: 1,
      ocr: 2,
      extract: 3,
      finalize: 4,
    },
    // Dwell minimo per fase (ms). Il backend completa analyze+classify in <1s
    // ma vogliamo che la UI mostri ogni step come "in lavorazione" per il
    // tempo indicato: l'attesa per l'AI si percepisce distribuita sull'intera
    // pipeline, non concentrata sull'ultimo step.
    minPhaseMs: [10000, 10000, 3000, 4000, 1500],
    copy: {
      formatError: 'Formato non supportato (solo .pdf)',
      tooLargeError: 'File troppo grande (max 20 MB)',
      invalidFileError: 'Non siamo riusciti a leggere questo PDF. Prova con un file diverso.',
    },
  });
}

window.dietImporterPdf = dietImporterPdf;
