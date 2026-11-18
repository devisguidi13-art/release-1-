# DVS Music 1.0.6 — Music First (iPhone)

Questa versione parte dai sorgenti **1.0.5 forniti dall'utente**. La grafica SwiftUI, la libreria, i preferiti, le playlist, la radio intelligente, i generi, le classifiche e il player `AVQueuePlayer` sono conservati.

## Cosa cambia

1. `YouTubeMusicCatalog.swift` aggiunge una **ricerca di brani e metadati YouTube Music**. Analizza i risultati musicali del web client, estrae titolo, artista, durata, copertina e **video ID**, e scarta risultati senza un ID utilizzabile. Questo è un adattamento Swift originale del concetto *music-first* studiato in SimpMusic; **non incorpora né copia il suo codice Kotlin GPL-3.0**.
2. `MultiSourceCatalog.search` cerca in parallelo **YouTube Music**, **YouTube/Invidious** e **Audius**. Vengono privilegiate corrispondenze musicali pertinenti e indizi di origine musicale (Topic/VEVO); il nome YouTube Music non è una certificazione di account ufficiale.
3. Se un brano non è riproducibile, il catalogo cerca **prima un altro video ID della stessa registrazione** tramite i due motori di ricerca YouTube, controllando artista, titolo, durata e versioni (remix/live/slowed ecc.). Solo dopo prova Audius, quando esiste una corrispondenza abbastanza precisa.
4. I brani YouTube Music usano **lo stesso player YouTubeKit** già presente: non c'è un player esterno. Audius conserva il proprio endpoint di streaming tramite API.
5. I dati precedenti restano compatibili: il nuovo campo facoltativo `catalogOrigin` non altera gli ID delle tracce YouTube, le playlist o la cronologia precedenti.
6. Il workflow GitHub Actions crea l'IPA **1.0.6** e include test offline per ricerca/parsing, disambiguazione delle versioni e regressioni delle versioni precedenti.

## Limiti e trasparenza

- **SimpMusic non viene compilato su iPhone.** È una app principalmente Kotlin/Android/Desktop. Questa release implementa un motore Swift autonomo che riprende la sua strategia di ricerca. Non abbiamo copiato moduli SimpMusic.
- YouTube Music e YouTube **non sono due fornitori audio indipendenti**. Condividono la stessa infrastruttura. Questo migliora l'individuazione di brani mainstream e possibili alternative video, ma non crea un catalogo commerciale con licenza aggiuntiva.
- La ricerca YouTube Music usa un'interfaccia **web non ufficiale**. La configurazione viene letta dalla pagina pubblica attuale, senza credenziali o chiavi hardcoded. Può essere modificata/bloccata: in quel caso il motore torna ai risultati YouTube/Invidious e Audius.
- Il precedente risolutore YouTubeKit usa interfacce non ufficiali; non è garantito che ogni brano riproduca su iPhone, né che il background playback sia ammesso dalle condizioni YouTube. Le API ufficiali YouTube vietano separazione audio/video e riproduzione tramite player nascosti. Valutare i termini prima della distribuzione.
- **Verificati:** compilazione e test dei moduli Foundation su Linux, parsing Swift e regressioni offline 0.8–1.0.5. **Non verificati:** build Xcode/iOS e API/riproduzione reali; richiedono GitHub Actions e prova sul dispositivo.

## Aggiornamento manuale sul repository GitHub

1. Estrai lo ZIP e copia **tutti i file** nel repository mantenendo la struttura, soprattutto `native-ios/DVSMusic/`, `.github/workflows/crea-ipa.yml` e `tests/`. Conferma l'overwrite dei file esistenti.
2. Fai commit delle modifiche.
3. Nella scheda **Actions** apri **DVS Music 1.0.6 - Music First iPhone**, scegli **Run workflow**.
4. A build verde scarica l'artifact **DVS_Music_106_iPhone_IPA_non_firmato**; poi firma e installa l'IPA con la procedura già usata per la 1.0.5.

### Cosa provare sull'iPhone

- Cercare un brano commerciale italiano e uno internazionale, controllando l'etichetta **YouTube Music**, la durata e la copertina.
- Selezionare il brano, verificare che riproduca e che il passaggio alla traccia successiva non interrompa la coda.
- Controllare la stessa canzone in due versioni (originale, remix): il fallback non deve sostituire un remix all'originale.
- Verificare che preferiti e playlist salvati nella 1.0.5 siano ancora presenti.

Fonte di ispirazione architetturale: https://github.com/maxrave-dev/SimpMusic (GPL-3.0). Documentazione dei limiti YouTube: https://developers.google.com/youtube/terms/developer-policies/.
