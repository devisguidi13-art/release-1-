# DVS Music 0.8 — Interfaccia Premium (iPhone)

Questa è una revisione grafica del progetto **DVS Music 0.8**, basata sul concept approvato: dark mode, verde brillante, carte visuali, miniplayer persistente e icona nera con simbolo musicale verde **senza testo**.

## Schermate rinnovate

- **Home:** saluto dinamico, filtri, preferiti/cronologia/replay, mix fotografici, Mood e accesso a Discovery.
- **Player:** copertina grande e sfondo dinamico, seek, play/pausa, avanti/indietro, shuffle/ripeti, radio, testi, timer, modalità notte e coda.
- **Cerca:** barra di ricerca, pulsanti ricerca vocale e riconoscimento, generi a mosaico.
- **Mood e Discovery:** immagini locali, 8 atmosfere, radio, Smart Shuffle, Discovery Swipe e controlli ascolto.
- **Libreria:** preferiti, playlist manuali, cronologia, playlist automatiche e playlist intelligenti.
- **Wrapped:** grafica verde con **statistiche reali locali**, top artisti e brani più ascoltati.
- **Profilo:** raggiungibile dall'icona impostazioni nella Home. Qui restano i controlli radio, algoritmo, Last.fm e modalità notte.

Quattro schede principali: **Home, Cerca, La tua libreria, Wrapped**. Mood e Scopri sono accessibili dalla Home, il Profilo dalle impostazioni. Tutti i comandi grafici principali restano collegati alle azioni esistenti della 0.8.

## Icona

Il file iOS è `native-ios/DVSMusic/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024×1024); la versione Expo è `assets/icon.png`. L'icona è un simbolo originale con onde verticali e play triangolare, su sfondo nero e senza la scritta DVS Music.

## Conservazione del progetto 0.8

Non sono state modificate le implementazioni del playback, di Last.fm, della ricerca YouTube, della cronologia, dello store locale o dei servizi microfono/ShazamKit. Sono rimaste invariate le chiavi UserDefaults per mantenere preferiti, playlist e cronologia quando iOS conserva i dati dell'app con lo **stesso bundle ID** (`app.dvsmusic.native`). Prima di sostituire una build su cui conservi dati importanti, fai un backup: con alcune procedure di sideload la reinstallazione può cancellare i dati.

Crossfade, equalizzatore e normalizzazione LUFS reali **non sono stati aggiunti**: servirebbe una modifica strutturale alla pipeline audio.

## Come compilare l'IPA su GitHub

1. Estrai tutto lo ZIP e carica il contenuto alla **radice del repository GitHub** della versione funzionante, conservando le cartelle `.github`, `native-ios`, `assets` e `tests`.
2. Apri la scheda **Actions** e seleziona **DVS Music 0.8 - iPhone audio nativo**.
3. Premi **Run workflow**. La pipeline esegue i test e compila su un runner macOS con Xcode.
4. Se la compilazione termina in verde, apri **Artifacts** e scarica l'IPA non firmato; serve il consueto sistema di firma/sideload per installarlo.

## Cosa è stato testato

- Test Swift del motore, delle playlist e statistiche locali: superati.
- Test Node/TypeScript per la coda e i collegamenti di ricerca: superati.
- Parsing dei sorgenti Swift: superato.
- Esistenza e dimensioni degli asset: verificate.

**Non eseguiti**: type-check completo SwiftUI per iOS, compilazione Xcode e test sul dispositivo. Eventuali problemi rilevati da GitHub Actions richiederanno correzioni puntuali. Il documento e il pacchetto non certificano che la build sia già installabile.

I visual originali dei Mood e Mix derivano dal mockup grafico approvato e sono inclusi come asset statici locali. Gli album dei singoli brani provengono invece dalle copertine del catalogo già usato dalla 0.8.
