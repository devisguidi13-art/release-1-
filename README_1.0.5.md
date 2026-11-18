# DVS Music 1.0.5 — Multi motore 100% interno (iPhone)

- Recupera tutte le funzioni della 1.0.4: coda intelligente, player AVQueuePlayer, radio continua, 20 generi, classifiche/uscite dinamiche, preferiti, mix, ricerca e UI.
- SoundCloud link esterno e icone dei link Apple Music rimossi dalle classifiche. Nessun player esterno.
- Ricerca simultanea in due **cataloghi con audio**: YouTube (risolutore non ufficiale preesistente) e Audius (API pubblica per streaming). YouTube viene preferito per corrispondenze ufficiali Topic/VEVO, quando rilevabili; deduplica delle versioni.
- Se il flusso principale fallisce durante risoluzione **o** riproduzione, DVS tenta la **stessa registrazione** sull'altra sorgente e usa lo stesso AVQueuePlayer. Non forza una corrispondenza se non è sufficientemente certa (artista, titolo e durata).
- Artwork Audius e file di libreria legacy compatibili: la migrazione non cancella playlist/storico.
- Non c'è nessuna chiave da inserire nell'app per iniziare a provare gli endpoint pubblici Audius. L'API può applicare limiti o richiedere API key per quote maggiori.

## Disponibilità
Audius ha un catalogo differente da YouTube e **non garantisce** le versioni mainstream o le principali uscite Spotify. Non sostituisce gli accordi di licenza dei servizi a pagamento. SoundCloud API ora richiede credenziali ed esistono vincoli su stream e preview; non va spacciata per una sorgente integrabile gratuitamente e universalmente.

## Installazione manuale con GitHub
1. Scompatta lo ZIP e sostituisci nel repository il contenuto mantenendo le cartelle `native-ios/`, `.github/workflows/`, `tests/`.
2. Apri la scheda **Actions** e scegli **DVS Music 1.0.5 - Multi Motore Interno iPhone** → **Run workflow**.
3. Se la compilazione è verde, scarica l'artifact **DVS_Music_105_iPhone_IPA_non_firmato** e firma/installa con il metodo già usato per la 1.0.4.

### Verifiche
La sintassi Swift e test core possono essere verificati in ambiente Linux. La compilazione completa iOS, l'accessibilità live dei provider e la riproduzione su iPhone richiedono GitHub Actions/Xcode e prova reale: non vanno dichiarati verificati prima di aver eseguito la build.

### Nota piattaforme
YouTubeKit + Invidious: interfacce non ufficiali, con possibili interruzioni e incompatibilità con le condizioni di YouTube (audio-only/background). Per distribuzione pubblica occorre valutare le regole dei servizi. Audius usa solo risorse accessibili via API ufficiale.
