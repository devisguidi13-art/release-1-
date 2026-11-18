# DVS Music 1.0.1 — app iOS nativa (audit)

Vedi [`AUDIT_1.0.1.md`](../AUDIT_1.0.1.md) per correzioni, verifiche e limitazioni di questa release.

# DVS Music 0.8 — app iOS nativa

Vedi [`README_0.8.md`](../README_0.8.md) per funzioni, limiti, permessi e istruzioni di build.

# DVS Music 0.7 — base preservata

`DVSMusic/` contiene l'app compilata da XcodeGen; `project.yml` dichiara automaticamente tutti i file `.swift` aggiunti.

Nuovi moduli 0.7:
- `MusicMetadata.swift`: normalizzazione artista/titolo dei risultati video.
- `LastFMService.swift` e `RecommendationEngine.swift`: similarità Last.fm facoltativa e radio locale con cronologia/preferiti.
- `ListeningStore.swift`: statistiche e blocchi brani locali, DVS Wrapped.
- `LyricsService.swift`: ricerca LRCLIB e parser dei testi LRC temporizzati.
- `PlaybackController.swift`: timer, radio, mix del giorno, Smart Shuffle, storico.
- `ContentView.swift`: player, profilo, timer, lyrics, DVS Wrapped.

Compilazione GitHub: `.github/workflows/crea-ipa.yml`. Build Mac locale: `brew install xcodegen`, `cd native-ios`, `xcodegen generate`, apri il progetto generato e compila con Xcode.

### Fattibilità audio
`AVQueuePlayer` mantiene la riproduzione remota già esistente; **crossfade con sovrapposizione reale**, **equalizzatore** e **normalizzazione LUFS** non sono state aggiunte perché necessitano una pipeline DSP e verifiche di compatibilità sul formato stream. Vedi `README_0.7.md` alla radice.

Le sorgenti YouTubeKit/Invidious non sono ufficiali, possono essere instabili e possono violare le condizioni di accesso dei rispettivi provider.
