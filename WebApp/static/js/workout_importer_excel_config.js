// Alpine entry for Excel workout import (sync).
function workoutImporterExcel() {
  return window.createWorkoutImporter({
    sourceType: 'excel',
    accept: '.xlsx,.xls',
    extPattern: /\.(xlsx|xls)$/i,
    maxBytes: 10 * 1024 * 1024,
    submitUrl: '/api/allenamenti/import/excel/',
    async: false,
    showSourceBadge: false,
    minPerceivedMs: 4500,
    steps: [
      { icon: 'ph ph-file-xls', label: 'Lettura file Excel...' },
      { icon: 'ph ph-brain', label: 'Analisi AI in corso...' },
      { icon: 'ph ph-link', label: 'Match esercizi nel database...' },
    ],
    motivationalMessages: [
      'Sto identificando le sessioni della scheda...',
      'Sto riconoscendo gli esercizi...',
      'Sto interpretando sets, reps e carichi...',
      'Sto cercando i match nel database esercizi...',
    ],
    copy: {
      formatError: 'Formato non supportato (solo .xlsx/.xls)',
      tooLargeError: 'File troppo grande (max 10 MB)',
      invalidFileError: 'Il file non è leggibile. Prova con un altro formato.',
    },
  });
}
window.workoutImporterExcel = workoutImporterExcel;
