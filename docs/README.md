# Athlynk · Codex

Documentazione del codice della piattaforma Athlynk — l'API mobile Django (`/api/v1`)
e l'app atleta iOS (SwiftUI).

## Come si apre

`docs/index.html` è un sito statico autonomo (nessuna build, nessuna dipendenza).
Aprilo nel browser:

```bash
open docs/index.html          # macOS
# oppure servilo:
python -m http.server -d docs 8080   # poi http://localhost:8080
```

## Cosa contiene

- **Panoramica** — sistema, architettura, ciclo di vita della richiesta.
- **Modello di sicurezza** — postura difensiva ad alto livello.
- **Backend** — auth & token, reference dei 35 endpoint `/api/v1`, modelli di dominio.
- **iOS** — Core (AppState, APIClient, DTO), design system (Theme, Components), Features.

Stile: estetica proprietaria Athlynk (greca-lusso) — Bodoni Moda / Spectral / JetBrains Mono,
pergamena, bronzo, Egeo. Struttura tipo Doxygen (moduli → simboli con firma e scopo).

## Sicurezza — cosa NON è qui (di proposito)

Questa documentazione descrive **come** funziona la sicurezza, non le sue debolezze.
Il report di audit dettagliato (vulnerabilità, vettori, mitigazioni interne, segreti)
**non** va versionato nel repo: documentare le debolezze equivale a dare una mappa
all'attaccante. Tienilo in un canale privato (gestore password / wiki interna / issue privata).

I segreti (`SECRET_KEY`, `DATABASE_URL`, credenziali SMTP/APNs) vivono solo nelle
variabili d'ambiente, mai nel codice né nei documenti.

## Manutenzione

Il sito è scritto a mano dai sorgenti, non auto-generato a ogni build. Quando aggiungi
o modifichi endpoint / modelli / viste, aggiorna la sezione corrispondente in
`docs/index.html` (cerca il nome del simbolo).
