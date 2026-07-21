# Athlynk — Android (Flutter)

Le app Android di Athlynk sono la controparte Flutter delle due app iOS
(`iOS/Athlynk`): stessa esperienza, stessi dati, stessa identità visiva, ma
native su Android. Non c'è logica di prodotto duplicata — leggono lo stesso
backend delle app iOS, quindi restano allineate da sole.

L'identità visiva è condivisa con web e iOS: blu profondo `#1E3A5F`, accento
azzurro `#5B89B6`, oro `#FFE066`, titoli Bodoni Moda e testo Inter (definiti nel
tema Flutter, gli stessi valori di `WebApp/static/css/athlynk.css` e del tema
iOS).

Un solo progetto Flutter, due app:

| App | Flavor | applicationId | Entry point | Scheme |
|---|---|---|---|---|
| Athlynk (atleta) | `athlete` | `it.athlynk.athlynk` | `lib/main_athlete.dart` | `athlynk://` |
| Athlynk Coach | `coach` | `it.athlynk.athlynk.coach` | `lib/main_coach.dart` | `athlynkcoach://` |

Backend: Django su `https://app.athlynk.it` — `/api/v1/*` (atleta),
`/api/v1/coach/*` (coach) e il tier dual-auth `/api/...` usato dai builder
del coach (gli stessi endpoint della dashboard web).

---

## Avvio rapido

```bash
cd android
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Freezed / json_serializable

./scripts/run_athlete.sh          # atleta su prod (app.athlynk.it)
./scripts/run_coach.sh dev        # coach su localhost:8000
```

`flutter run` diretto:

```bash
flutter run --flavor athlete -t lib/main_athlete.dart --dart-define-from-file=env/prod.json
flutter run --flavor coach   -t lib/main_coach.dart   --dart-define-from-file=env/prod.json
```

## Build

```bash
./scripts/build.sh debug apk prod          # APK debug di entrambe le app
./scripts/build.sh release appbundle prod  # AAB per Play Store
```

Output in `build/app/outputs/flutter-apk/`:
`app-athlete-debug.apk`, `app-coach-debug.apk`.

> Per la release serve un keystore: crea `android/key.properties` e collega
> un `signingConfig` in `android/app/build.gradle.kts` (oggi la release usa
> ancora le chiavi di debug, come nel template Flutter).

## Test

```bash
./scripts/test.sh                 # codegen + analyze + unit/widget (70 test)
./scripts/test.sh --integration   # + flusso e2e su device/emulatore
```

- **Unit** — retry/backoff e mapping errori del client HTTP, parsing SSE,
  round-trip `fromJson` sui payload reali del backend, TTL della cache,
  RPE↔RIR, `DietWeekday`, formattazione `it_IT`, brand theme, push bridge,
  macchina a stati della sessione (bootstrap 401-vs-offline, login, terms,
  logout).
- **Widget** — login (render, errore 401, token salvato, occhio password),
  editor della dashboard (ordine canonico, aggiungi/rimuovi/reset),
  design system (NeonButton, ConfirmCenter, EmptyPanel, toggle ottimistico,
  token del tema).
- **Integration** — `integration_test/athlete_flow_test.dart`: splash →
  login → shell 5 tab → widget dashboard dal server → cambio tab, contro un
  backend stubbato.

---

## Struttura

```
lib/
  main_athlete.dart · main_coach.dart   entry point per flavor
  app/            bootstrap, MaterialApp, router di fase (splash/login/app)
                  + i 3 cover bloccanti (terms → chiron → review)
  core/
    config/       AppConfig (--dart-define-from-file)
    l10n/         stringhe condivise + formatter it_IT
    network/      ApiClient (Dio, retry ×2, error mapping, SSE), ApiException
    auth/         SessionController (porting di AppState), TokenStorage
    cache/        MemoryCache TTL 5 min (chiavi delle due dashboard)
    models/       ~110 DTO Freezed (auth, workouts, session, nutrition,
                  checks, chat, billing, dashboard, progress, profile, coach)
    api/          athlete_api.dart · coach_api.dart (una funzione per endpoint)
    push/         PushBridge (remote-change bus) + notifiche locali
    analytics/    wrapper PostHog (no-op finché manca la key, come iOS)
    utils/        haptics, compressione immagini, Stripe web flow,
                  DietWeekday, RPE↔RIR
  design/
    theme.dart    Palette (hex identici a iOS), Typo, Space, Motion, BrandTheme
    components/   ~30 componenti condivisi: VoltBackground, VoltPanel,
                  NeonButton, tab bar flottante, skeleton, grafici custom,
                  RingGauge, ParticleBurst, ConfirmCenter, sheet, mascotte…
  features/
    shared/       splash, login, password dimenticata, onboarding, terms, review
    athlete/      dashboard, workouts + sessione live + rest timer, nutrition
                  (FOOD/MACRO), check, progressi, chat, agenda, abbonamento,
                  checkout, notifiche, profilo, aiuto, tutorial Chiron
    coach/        dashboard, atleti, check (review/modelli/builder), piani
                  (wizard/builder/progressioni/import AI/cartelle), agenda,
                  analytics, messaggi, Chiron (SSE), abbonamenti + Connect,
                  risorse/integratori, profilo, wizard onboarding
test/ · integration_test/ · scripts/ · env/
```

## Scelte architetturali

**Un progetto, due flavor.** Rispecchia il progetto Xcode (due target che
condividono `Shared/`): un solo `pubspec`, core e design system condivisi,
due entry point con `FlavorConfig` (titolo, splash, shell, wizard,
onboarding). Il `flavorProvider` porta con sé anche il ruolo di login
(`CLIENT`/`COACH`) e lo scheme dei redirect Stripe.

**Riverpod** per lo stato: provider globali (sessione, API client, cache,
push, rest timer) + `Notifier` per le schermate con logica vera (dashboard,
sessione attiva). Le altre schermate restano `State` + `load()` async, come
su iOS — la complessità è la stessa dell'originale, non di più.

**Navigazione senza go_router.** Le due app usano un `IndexedStack` di
`Navigator` per tab (stack indipendenti, pop-to-root al re-tap), che è
l'equivalente 1:1 del `NavigationPath`-per-tab di SwiftUI; i flussi modali
usano `showAppSheet` (bottom sheet con Navigator annidato) come i `.sheet`
iOS. `go_router` avrebbe imposto un modello di rotte che l'app iOS non ha
(non esiste deep linking sull'atleta; sul coach solo i link di Chiron, che
sono gestiti da `chiron_router.dart`).

**Dio + Freezed.** `ApiClient` replica il comportamento di `APIClient.swift`:
timeout 20 s, retry ×2 con backoff lineare 400 ms su 5xx ed errori di rete,
e i tre soli messaggi utente italiani (connessione / credenziali / generico),
mai la stringa grezza del server. I DTO sono generati da Freezed con
`fieldRename: snake`, con `@JsonKey` dove il wire diverge (es. `carbs`
plurale sull'atleta vs `carb` singolare sul coach: due serializer diversi,
entrambi corretti).

**Token in `flutter_secure_storage`** (Keystore), mai in SharedPreferences —
parità con il Keychain iOS. Nessun refresh token: come sul backend, un 401
in bootstrap fa logout, un errore di rete no (mantiene il token e mostra
"Riprova").

**Design system prima delle schermate.** `theme.dart` porta i token esatti
di `Theme.swift` (parchment/marble/ink, royal blue + oro, Bodoni Moda per il
display, JetBrains Mono per i numeri). I nomi legacy (`voltPanel`,
`NeonButton`, `Palette.magenta`) sono mantenuti apposta: rendono banale il
confronto file-per-file con il codice iOS.

**Grafici scritti a mano** (`CustomPainter`) invece di una libreria: i
grafici iOS sono `Path` native con drag-to-scrub e tooltip, e replicarli è
l'unico modo per avere la stessa resa.

## Adattamenti Android

- **Rest timer**: al posto della Live Activity, notifica *ongoing* con
  cronometro in conto alla rovescia (`flutter_local_notifications`), più la
  stessa pill in-app.
- **Stripe**: Custom Tab / browser + intent-filter sullo scheme del flavor,
  con `app_links` a catturare `checkout-return` / `connect-return`. Nessun
  IAP: il prodotto non lo usa, il fulfillment resta server-side via webhook.
- **Back di sistema**: gestito con `PopScope` — pop nello stack del tab
  attivo, conferma prima di abbandonare una sessione di allenamento.
- **Glass**: la tab bar flottante usa `BackdropFilter` + tint, con il blob
  animato che si sposta sotto il tab attivo (equivalente di
  `matchedGeometryEffect`).
- **WebP animate**: Flutter le decodifica nativamente, quindi le demo degli
  esercizi non hanno bisogno dell'hack `WKWebView` di iOS.
- **Ripple**: sostituito dal press-scale 0.97 del brand su card e CTA;
  resta quello standard sui controlli Material puri.
- Edge-to-edge con icone scure di status bar sul tema chiaro.

## Configurazione ambienti

`env/dev.json` → `http://localhost:8000` · `env/prod.json` →
`https://app.athlynk.it`. Le chiavi (`API_BASE_URL`, `ENVIRONMENT`,
`POSTHOG_API_KEY`, `POSTHOG_HOST`) rispecchiano gli xcconfig iOS e arrivano
in `AppConfig` via `--dart-define-from-file`.

---

## Cosa manca (dipendenze esterne, non codice)

1. **Push server-side.** Il backend invia solo APNs (`config/services/push.py`).
   Il client Android è pronto: `POST /api/v1/devices/register` viene chiamato
   con `platform: "android"` (il modello `DeviceToken` lo supporta già) e il
   `PushBridge` smista gli eventi per `type` esattamente come
   `onRemoteChange` su iOS. Servono: un sender FCM lato Django e il
   `google-services.json` nel progetto. Finché non ci sono, l'app resta
   pienamente funzionante (tutti gli aggiornamenti sono pull-based:
   pull-to-refresh, foreground, polling chat ogni 4–5 s).
2. **Firma di release**: `key.properties` + `signingConfig` (oggi debug keys).
3. **PostHog**: `POSTHOG_API_KEY` vuota ⇒ analytics no-op, come su iOS oggi.
4. **Icona del launcher**: generata dall'`AppIcon.png` iOS (identico per le
   due app: se le vuoi distinte serve l'asset coach).
5. **Font**: Didot non esiste su Android → **Bodoni Moda** (il sostituto
   indicato dai commenti nel codice iOS); SF → **Inter**, SF Mono →
   **JetBrains Mono**. Tutti bundlati e OFL.
6. **Icone**: gli SF Symbols sono mappati a mano su Material Symbols per
   significato (non esiste un equivalente 1:1).
7. **Mascotte Chiron**: l'asset `ChironCentaur` non esiste nemmeno nel
   progetto iOS → è portato il fallback generato (sigillo bronzo + icona
   arciere, aura, anello tratteggiato, bob).
8. **Import piani (coach)**: il file picker usa `image_picker` (media). Per
   accettare PDF/XLSX dal file manager basta sostituirlo con `file_selector`
   in un solo punto (`coach_plan_import_view.dart`).
9. **Dark mode**: iOS forza `.preferredColorScheme(.light)` e l'app Android
   fa lo stesso; i token sono comunque strutturati per aggiungerla.
10. **"Nuovo Check" lato atleta**: placeholder anche su iOS (manca l'endpoint
    di creazione lato backend) → resta tale.

## Parità con iOS

- **Atleta**: splash, onboarding, login, password dimenticata, terms gate,
  tutorial Chiron, review prompt, dashboard a widget (ordine canonico e
  autosave 600 ms sincronizzati con la griglia web), schede → giorno →
  esercizio, sessione live (log serie con validazione + shake, aggiungi/
  sostituisci/rimuovi solo-sessione, rest timer), storico, nutrizione
  FOOD/MACRO × DAILY/WEEKLY, diario macro + ricerca alimenti + storico,
  integratori, check multi-step (8 tipi di domanda), success, storico check
  con Calcolo Fabbisogni read-only, andamento (grafici peso/circonferenze/
  pliche, confronto foto, trend per esercizio), percorso, agenda, chat con
  appuntamenti, abbonamento/prezzi/checkout Stripe, notifiche, profilo
  (modifica, aspetto, calendario, legal, logout, elimina), aiuto.
- **Coach**: splash/login/onboarding, wizard profilo Chiron, dashboard a
  widget + atleti in evidenza, roster + creazione atleta, scheda cliente
  (progressi, percorso con fasi, sessioni, check, diario macro, misurazioni),
  review check con feedback, libreria modelli, builder a blocchi,
  assegnazione con ricorrenza, libreria piani, wizard scheda/dieta con
  builder nativo e unificazione RIR↔RPE, griglia progressioni, import AI,
  cartelle, agenda + prenotazione, analytics (KPI business, churn risk,
  ring revisioni, volumi), messaggi + messaggi automatici, Chiron AI in
  streaming SSE con azioni e deep link, abbonamenti + Stripe Connect + CRUD
  piani, risorse e protocolli integratori, profilo con billing portale
  piattaforma.
