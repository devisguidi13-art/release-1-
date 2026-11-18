# DVS Music 0.8 — Personal Edition per iPhone

Versione **da compilare e verificare su iPhone**. Progetto iOS nativo in `native-ios/`, basato direttamente sulla 0.7: non è una nuova app, non è l'app Expo di backup. `native-ios/project.yml` mantiene lo stesso bundle ID `app.dvsmusic.native` e i salvataggi precedenti.

## Funzioni 0.8

1. **DVS Mood:** 8 atmosfere selezionabili nella scheda *Scopri*. Cerca nel catalogo brani associati al mood tramite parole e poi avvia radio. È una classificazione euristica, **non un'analisi del segnale audio**, dei BPM o della tonalità.
2. **Discovery Swipe:** nuova scheda con gesture a destra per mettere nei preferiti e a sinistra per segnalare uno skip. Gli skip vengono conteggiati nell'apprendimento locale; non bloccano permanentemente il brano. Tasto *Ascolta* per provare la canzone.
3. **Player dinamico:** la sfumatura della pagina player (e della modalità notte) adotta un colore estratto dalla copertina scaricata; se non è disponibile, rimane il verde DVS.
4. **Cronologia intelligente:** ricerca per artista/titolo, data e ora per i nuovi eventi di riproduzione. La 0.7 registrava conteggi aggregati, quindi non è possibile ricostruire data e ora esatte per i vecchi ascolti.
5. **Playlist automatiche:** Più ascoltati, Ultimi 30 giorni, Preferiti del momento, Da riscoprire. Si aggiornano senza creare copie statiche; derivano dai dati sul dispositivo.
6. **Ricerca vocale:** microfono nella barra Cerca; usa il framework Speech Apple in italiano, richiede il permesso microfono e riconoscimento vocale. Su alcuni dispositivi e lingue richiede Internet. Interrompe temporaneamente il player e lo riprende a fine registrazione.
7. **Riconoscimento musicale:** pulsante a forma d'onda accanto al microfono. Usa ShazamKit per ascoltare dal microfono la musica ambientale e, se la riconosce, avvia una ricerca per artista e titolo; *non* importa automaticamente il brano da Shazam e non analizza i flussi interni di DVS. Richiede permesso microfono, rete/catalogo Shazam e potrebbe richiedere l'attivazione del servizio ShazamKit nelle capacità dell'App ID Apple quando si firma/installata.
8. **Playlist intelligenti:** crea regole su parole presenti in titolo/artista, preferiti, numero minimo di ascolti, finestra temporale. Aggiornamento continuo. Non esiste un rilevamento affidabile del genere senza metadati esterni.
9. **Modalità notte:** schermata scura e minimale con player, timer, comandi grandi e tasto Esci. La preferenza resta memorizzata.
10. **Controllo dell'algoritmo:** slider tra *familiarità* e *scoperta* nel Profilo. Influisce sul ranking locale dei suggerimenti e sullo Smart Shuffle, non sul ranking proprietario dei provider esterni.

## Conservato dalla 0.7

- Player `AVQueuePlayer` nativo, audio in background, controlli da schermata di blocco, YouTubeKit/AudioResolver esistenti, ricerca e coda.
- Radio da brano, Last.fm gratuito opzionale, Smart Shuffle, mix giornalieri, esclusione permanente dal menu del brano, timer musica, LRCLIB e DVS Wrapped.
- **Stesse chiavi UserDefaults**: `dvs-native-favorites`, `dvs-recent-v06`, `dvs-playlists-v06`, `dvs-listening-v07`, `dvs-blocked-v07`, `dvs-lastfm-api-v07`.
- La codifica del vecchio snapshot di ascolti continua a essere decodificata grazie al nuovo campo `playEvents` opzionale.

## Limiti / cosa non promettiamo

- I nuovi mood e la ricerca per affinità sono indicativi; non possediamo gli stessi dati e modelli di Spotify.
- **Crossfade reale, equalizzatore e normalizzazione LUFS non sono in 0.8**. Non vengono inventati controlli fittizi; il player 0.7 resta intatto.
- Le API pubbliche di Invidious, le informazioni Last.fm e il catalogo Shazam possono essere intermittenti o inaccessibili. Il backend YouTube non ufficiale presente già nella 0.7 può smettere di funzionare ed essere incompatibile con i termini del fornitore.
- Le autorizzazioni non vengono richieste all'avvio: solo al tap delle funzioni che usano il microfono. Apple potrebbe usare server per la trascrizione e ShazamKit usa il servizio di riconoscimento.
- **L'IPA nel workflow è non firmato**: occorre firmarlo con un metodo Apple valido. Prima serve una build verde e un test reale delle funzioni che usano Apple Speech e ShazamKit.

## Installazione con GitHub Actions

1. Estrai lo ZIP sul PC.
2. Carica **tutti i file e le cartelle della radice** nel repository GitHub della 0.7, sostituendo gli omonimi. Non caricare una sola cartella contenitore, e verifica che `.github/workflows/crea-ipa.yml` sia presente.
3. Apri **Actions → DVS Music 0.8 - iPhone audio nativo → Run workflow**.
4. Il workflow esegue test della 0.7 e della 0.8, verifica l'Info.plist, installa XcodeGen, compila il progetto nativo e crea `DVS_Music_v08_unsigned.ipa` dentro l'artefatto `DVS_Music_08_iPhone_IPA_non_firmato`.
5. Firma l'IPA come facevi con la 0.7. Se ShazamKit non dovesse funzionare pur dopo la compilazione, controlla la configurazione della capability ShazamKit dell'App ID e i permessi del microfono. Gli altri servizi non dipendono da ShazamKit.

## Stato verifiche

- Test Swift su Linux: Foundation-only della 0.7 e della 0.8, passati.
- Parser Swift degli script iOS, passato.
- Test eseguibili del player e del microfono su iPhone: **non eseguiti in questa sede**.
- Xcode/iOS SDK non disponibili in questo ambiente: **build IPA non certificata**; eventuali errori del workflow dovranno essere corretti dai log reali.
