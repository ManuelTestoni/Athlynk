# Athlynk · Codex

La documentazione del codice è passata a **`Website/docs/index.html`** —
è la versione pubblicata su [athlynk.it/docs/](https://athlynk.it/docs/)
(linkata dal footer del sito) ed è l'unica fonte tenuta aggiornata.

Questa cartella ospitava in precedenza un fork locale non deployato dello
stesso file, mai sincronizzato dopo la prima stesura: è finita per divergere
in silenzio dalla versione pubblica (mancavano intere sezioni aggiunte dopo).
Per evitare che succeda di nuovo, il fork è stato rimosso — un solo file,
una sola fonte di verità.

Per consultarla in locale:

```bash
open Website/docs/index.html          # macOS
# oppure servila:
python -m http.server -d Website/docs 8080   # poi http://localhost:8080
```

## Sicurezza — cosa NON è qui (di proposito)

Questa documentazione descrive **come** funziona la sicurezza, non le sue
debolezze. Il report di audit dettagliato (vulnerabilità, vettori,
mitigazioni interne, segreti) **non** va versionato nel repo: documentare le
debolezze equivale a dare una mappa all'attaccante. Tienilo in un canale
privato (gestore password / wiki interna / issue privata).

I segreti (`SECRET_KEY`, `DATABASE_URL`, credenziali SMTP/APNs/Supabase)
vivono solo nelle variabili d'ambiente, mai nel codice né nei documenti.

## Manutenzione

Il sito è scritto a mano dai sorgenti, non auto-generato a ogni build. Quando
aggiungi o modifichi endpoint / modelli / viste / componenti della web
console, aggiorna la sezione corrispondente in `Website/docs/index.html`
(cerca il nome del simbolo).
