# DVS Music 0.6 · Personal Edition (iPhone)

La cartella **native-ios** è l'app da compilare. Si basa sulla 0.5 che era stata corretta per la compilazione, e aggiunge le funzionalità:

- UI ridisegnata in SwiftUI: Home, Cerca, Discovery, Libreria, Profilo, mini-player e player a schermo intero.
- Radio intelligente: proposte da video correlati e ricerca artista, ordinate per artista, titolo, indizi di genere e durata, con rimozione duplicati e dei brani ascoltati di recente.
- Queue management con spostamento su/giù e rimozione dei prossimi brani senza fermare quello corrente.
- Preferiti, cronologia recente e playlist persistenti sul dispositivo.
- Controlli dalla schermata di blocco, audio in background e pre-caricamento dei prossimi brani usando AVQueuePlayer.
- Generazione automatica di un IPA **non firmato** con GitHub Actions.

## Compilazione iOS

1. Carica nella radice del tuo repository GitHub il contenuto di questo ZIP, **senza aggiungere un livello di cartella**.
2. Apri **Actions → DVS Music 0.6 - iPhone audio nativo (sperimentale) → Run workflow**.
3. Quando il job risulta verde, apri **Artifacts → DVS_Music_06_iPhone_IPA_non_firmato**.
4. L'IPA non è firmato: serve un metodo di firma valido per installarlo su iPhone.

**Limiti:** questa versione non è stata compilata su macOS in questo ambiente e può necessitare di piccole correzioni Xcode. Il catalogo si appoggia a istanze pubbliche Invidious e la riproduzione a YouTubeKit, interfacce non ufficiali che possono non funzionare o non essere consentite dalle condizioni del servizio. L'algoritmo di similitudine è euristico e non equivale a quello di Spotify. Nessun server personale richiesto.

La cartella radice Expo è il codice di backup e **non** la nuova UI 0.6. Usa `native-ios` per la versione iPhone.
