# DVS Music 0.7 — Personal Edition (iPhone)

Questa è l'evoluzione della **0.6 iOS nativa**: player, ricerca, playlist, preferiti e controlli blocco schermo restano nella cartella `native-ios`. La radice Expo è **solo il vecchio progetto di backup**: la UI 0.7 si compila con XcodeGen dalla cartella `native-ios`.

## Novità integrate

- **Radio da un brano** dal menu `⋯` o dal player, con coda infinita quando il catalogo risponde.
- **Coda migliorata**: usa dati di somiglianza tra brani di Last.fm con chiave personale gratuita facoltativa (`track.getSimilar`). Riassocia poi artista/titolo a risultati del catalogo esistente; senza chiave, usa il catalogo e preferenze locali. Non è un modello IA eseguito sul telefono né replica l'algoritmo proprietario di Spotify.
- **Smart Shuffle**: bilanciamento tra generi, artisti consecutivi e preferenze, non semplice casuale.
- **Mix del giorno** (DVS Mix, Discovery e Replay): semi scelti dalla cronologia/preferiti con variazione giornaliera, radio automatica per i nuovi brani. Servono ascolti precedenti.
- **Non consigliarmi questo brano**: esclusione permanente locale, con opzione per ripristinare dal menu del brano.
- **Timer musica**: 5–90 minuti, tempo personalizzato 1–1440 minuti, o stop alla fine del brano. Il timer è valido per la sessione corrente, non viene ripristinato se il processo viene terminato.
- **Testi sincronizzati** via ricerca su LRCLIB, se disponibili: tap sulla riga per andare al punto. Se disponibili solo testi non sincronizzati, mostra quelli.
- **DVS Wrapped**: minuti, brani, artisti e tracce più ascoltati, con statistiche **locali che iniziano dalla 0.7**.

## Cosa resta non implementato e perché

**Crossfade con sovrapposizione reale** e **equalizzatore / normalizzazione automatica LUFS** richiedono un'architettura audio diversa: il player attuale è `AVQueuePlayer`, basato su stream remoti di YouTubeKit. Una semplice UI non cambierebbe l'audio; `AVAudioMix` non supporta tutti gli stream (es. HLS). Per non peggiorare la riproduzione stabile della 0.6 queste tre elaborazioni DSP non vengono simulate né abilitate. Una futura implementazione richiede una pipeline audio compatibile e test su dispositivo fisico.

## Attivare la raccomandazione Last.fm (opzionale, gratis)

1. Crea una API key personale non commerciale su https://www.last.fm/api/account/create (soggetta ai termini e ai limiti Last.fm).
2. Apri **Profilo → Raccomandazioni avanzate** e inserisci la chiave (non il secret).
3. Tocca **Salva chiave Last.fm**. La chiave rimane in UserDefaults sul dispositivo; non caricarla nel repository.
4. Avvia **Radio da un brano**; l'app cerca un massimo di sette risultati Last.fm per volta e ripiega sul catalogo esistente se non ci sono risultati.

Last.fm richiede una chiave anche per l'API pubblica; usarla non impone un abbonamento, ma la disponibilità e i limiti possono cambiare. Il servizio LRCLIB è gratuito e non richiede una chiave. I servizi di ricerca e playback già presenti nella 0.6 (Invidious e YouTubeKit) sono **non ufficiali** e possono smettere di funzionare o essere incompatibili con le condizioni di accesso della piattaforma.

## Installazione / compilazione IPA

1. Estrai lo ZIP e carica **il contenuto** della cartella principale nel repository GitHub che usavi per la 0.6, sostituendo i vecchi file. Non caricare una cartella extra che contenga tutto.
2. Apri **Actions → DVS Music 0.7 - iPhone audio nativo → Run workflow**.
3. Dopo il job verde scarica **DVS_Music_07_iPhone_IPA_non_firmato** in Artifacts.
4. Firma l'IPA con un metodo iOS valido e installalo come facevi già per la 0.6. Il formato IPA non firmato non è direttamente installabile.

**Stato di verifica locale:** i file Swift sono stati analizzati sintatticamente in Linux e la logica Foundation-only è stata sottoposta a typecheck; i test JavaScript presenti nel backup sono passati. Non è stato possibile eseguire `xcodebuild`/testare su iPhone in questo ambiente; il workflow GitHub Actions deve confermare la compilazione completa e la compatibilità audio.
