> **Aggiornamento:** questa è la documentazione della 1.0 originale. Per la 1.0.1 con correzioni consultare [AUDIT_1.0.1.md](AUDIT_1.0.1.md). Usare il workflow **DVS Music 1.0.1 - iPhone Premium / Verifica bug**.

# DVS Music 1.0 — Radio più pertinente e passaggio rapido

## Priorità di questa release

L'utente ha chiesto di mantenere la Premium UI 0.8 e concentrare tutto sul fatto che, terminato un brano, **il successivo sia simile e inizi rapidamente**. Per questo la 1.0 NON aggiunge funzioni secondarie che possano rendere instabile il player.

### Modifiche effettive

1. **DVS Intelligence 1.0:** classificazione per somiglianza Last.fm (`track.getSimilar`) con chiave personale gratuita. Ogni brano candidato viene cercato nel catalogo e verificato per artista e titolo: non basta trovare un titolo che contiene una parola.
2. **Fallback controllato:** se manca una corrispondenza Last.fm, i video suggeriti dal catalogo sono considerati di confidenza inferiore. È un fallback, non analisi acustica; non ci sono BPM, timbro o embedding inventati.
3. **Apprendimento locale:** preferiti, ascolti e skip vengono considerati; tre skip con più skip che play possono escludere un brano dalla radio. Il comando "Non consigliarmi" resta disponibile.
4. **Niente doppioni:** prova a riconoscere la stessa registrazione con ID video diversi, usando artista+titolo normalizzati. Esclude clip non musicali, reazioni, karaoke e alcune versioni non originali.
5. **Scoperta indipendente dalla riproduzione:** la richiesta di nuovi suggerimenti è avviata in un task separato. La 0.8 poteva aspettare la rete PRIMA di preparare la coda.
6. **Preparazione audio anticipata:** AVQueuePlayer riceve in anticipo più elementi già risolti e tiene aggiornata la quantità di stream preparati nella schermata del player. Ciò riduce i vuoti, senza promettere un tempo di avvio fisso.
7. **Rete più efficiente:** le istanze di ricerca indipendenti vengono interrogate in parallelo anziché una dopo l'altra, con timeout brevi e cache temporanee in RAM di ricerca, suggerimenti, Last.fm e URL degli stream.
8. **Recupero da errori:** se uno stream non si risolve all'avvio, tenta il brano seguente; se la coda finisce mentre cerca suggerimenti, prova ad avviare automaticamente il blocco aggiunto. Ritenta con moderazione se i provider sono indisponibili.
9. **Nessuna migrazione dati:** preservati il bundle ID `app.dvsmusic.native`, le chiavi UserDefaults, le schermate della Premium UI e i metodi pubblici usati da Mood, playlist, Discovery e Wrapped.

## Requisito per la massima somiglianza possibile

Profilo → Last.fm → inserisci una **chiave API personale gratuita**. Last.fm restituisce affinità derivate dagli ascolti, non registrazioni audio. Senza chiave rimane un algoritmo più debole basato sulle correlazioni offerte dal catalogo e sulle preferenze locali. La chiave non è incorporata nell'IPA e non è necessaria per aprire l'app.

## Cosa NON è possibile garantire

- **Identità con Spotify: NO.** Spotify dispone di un catalogo ufficiale, dati comportamentali su larga scala e sistemi di raccomandazione proprietari. Il nostro punteggio non è una percentuale di accuratezza verificata.
- **Cambio sempre istantaneo: NO.** Quando sono già presenti elementi AVPlayerItem preparati, l'avanzamento può essere rapido; rete, buffering, URL scaduti e restrizioni esterne possono introdurre attese o interruzioni.
- **Crossfade, equalizzatore, volume LUFS: NON IMPLEMENTATI.** Per queste sorgenti richiederebbero un'architettura audio diversa; non introduciamo controlli fittizi.
- **Fonte streaming:** il progetto 0.8 usa Invidious e YouTubeKit, servizi non ufficiali che possono interrompersi o avere limitazioni. Le norme ufficiali di YouTube vietano tra l'altro di isolare l'audio nei client che usano le YouTube API Services e la riproduzione in background dei player API; prima di distribuire il progetto occorre verificare di usare sorgenti e modalità autorizzate.

## Test eseguiti in questa sessione

- Compilazione ed esecuzione su Linux del motore Foundation e dei test di normalizzazione, classificazione, duplicati, feedback negativo, shuffle, URL e libreria.
- Parsing (`swiftc -frontend -parse`) di tutti i file Swift.
- Test npm esistenti.
- Verifica degli asset e della struttura ZIP.

**NON eseguiti:** type-check completo dei framework Apple, compilazione IPA macOS/Xcode e collaudo sul telefono con accesso alle API reali. Questi passaggi vengono eseguiti dal workflow GitHub e dall'utente con un dispositivo.

## Compilazione dalla stessa repository della 0.8

1. Estrai lo ZIP e caricane il **contenuto**, inclusa la cartella nascosta `.github`, alla radice della repository GitHub usata per la 0.8.
2. Non cambiare il bundle ID se vuoi aggiornare l'app già installata; con alcuni metodi di sideload i dati si perdono comunque, quindi esegui un backup di playlist e preferiti prima di sostituirla.
3. **Actions → DVS Music 1.0 - iPhone Premium / Radio intelligente → Run workflow.** I test vengono eseguiti prima della build Xcode.
4. Quando la build è verde, scarica il file `.ipa` non firmato dagli **Artifacts**; deve essere firmato per l'installazione con il tuo metodo abituale.
5. Sul telefono, prova 10-15 passaggi tra canzoni, con e senza chiave Last.fm. Se compaiono errori, conserva i log di GitHub Actions e il messaggio mostrato nell'app.

## Documentazione

- [API Last.fm track.getSimilar](https://www.last.fm/api/show/track.getSimilar)
- [Apple AVQueuePlayer](https://developer.apple.com/documentation/avfoundation/avqueueplayer)
- [Norme YouTube API Services](https://developers.google.com/youtube/terms/developer-policies/)
