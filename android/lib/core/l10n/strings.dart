/// Shared Italian copy (errors, common actions, recurring empty states).
/// Screen-specific copy stays inline next to its widget — same convention as
/// the iOS codebase (100% hardcoded Italian) — but anything reused twice or
/// user-visible on failure paths lives here.
class S {
  S._();

  // Errors (parity with iOS `APIError.errorDescription`)
  static const errTransport = 'Problema di connessione. Controlla la rete e riprova.';
  static const errCredentials = 'Email o password errati.';
  static const errGeneric = 'Si è verificato un errore. Riprova.';
  static const errOffline = 'Connessione assente. Riprova.';

  // Common actions
  static const retry = 'Riprova';
  static const cancel = 'Annulla';
  static const confirm = 'Conferma';
  static const save = 'Salva';
  static const close = 'Chiudi';
  static const done = 'Fatto';
  static const next = 'Avanti';
  static const back = 'Indietro';
  static const skip = 'Salta';
  static const delete = 'Elimina';
  static const edit = 'Modifica';
  static const loadMore = 'Carica ancora';
  static const search = 'Cerca';

  // Auth
  static const login = 'Accedi';
  static const logout = 'Esci';
  static const email = 'Email';
  static const password = 'Password';
  static const forgotPassword = 'Password dimenticata?';
  static const forgotPasswordSent = "Se l'email è registrata, controlla la posta.";
  static const deleteAccount = 'Elimina account';

  // Check form validation (exact iOS strings)
  static const vRequired = 'Campo obbligatorio.';
  static const vPickOne = "Seleziona almeno un'opzione.";
  static const vPhotoRequired = 'Carica almeno una foto.';
  static const vNumberOnly = 'Inserisci solo un numero (es. 82,5).';
  static const vPositive = "Dev'essere un numero maggiore di 0.";
  static String vRange(String min, String max, String unit) =>
      'Valore non plausibile: usa un numero tra $min e $max $unit.';

  // Payments
  static const paymentFailed = 'Impossibile completare il pagamento. Riprova.';
  static const paymentCancelled = 'Pagamento annullato.';
}
