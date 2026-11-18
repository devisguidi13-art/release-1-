# DVS Music 1.0.3 — Radio indipendente, swipe e audio WhatsApp

## Problemi corretti

1. **La radio non usa più l'elenco `recommendedVideos` di YouTube.** Da un risultato di ricerca parte la riproduzione del singolo brano e la radio costruisce da sola la coda. Usa iTunes Search API **solo per metadati musicali pubblici** (artista, titolo, genere), cluster di artisti simili, cronologia/preferiti e, se configurata, Last.fm. Solo dopo aver deciso *quale canzone* ascoltare cerca una fonte audio YouTube con confronto preciso artista+titolo e priorità ai caricamenti Topic/VEVO. Gli algoritmi YouTube non scelgono il prossimo brano.
2. **Swipe brani:** trascinamento a sinistra = brano successivo, a destra = brano precedente anche dopo parecchi secondi di riproduzione. Funziona sia sul mini-player sia sulla copertina nel player; swipe verticale continua a scorrere la pagina.
3. **Player centrato:** tappando la copertina o il titolo del mini-player apre un player nativo a tutto schermo. Album art dimensionata in base al display, layout orizzontale centrato e contenuti scorrevoli su iPhone piccoli. Apertura coda differita alla chiusura del player, per evitare due presentazioni contemporanee.
4. **Audio WhatsApp:** ascolto di un vocale mette in pausa DVS; se iOS notifica che l'interruzione è terminata e la ripresa è consentita, DVS riattiva la sessione e riprende. In caso di rilascio ritardato, controlla nuovamente; tornando nell'app tenta la ripresa se era in riproduzione prima. Una pausa manuale non viene annullata.
5. **Varietà della coda:** rotazione di artisti per stile, preferenze e cronologia; rimozione doppioni e brani bloccati, riduzione delle ripetizioni dello stesso artista. La scelta dell'artista è un'euristica, non analisi vera dei BPM o del timbro.

## Come aggiornare manualmente GitHub

1. Scarica e decomprimi l'archivio. Mantieni le cartelle `.github`, `native-ios` e `tests`.
2. Nel **tuo repository GitHub esistente**, carica o sovrascrivi i file mantenendo identici i percorsi. **Non** creare una cartella `DVS_Music_1_0_3` dentro al repository.
3. Controlla che `native-ios/DVSMusic/MusicDiscoveryService.swift` sia presente (nuovo file) e che `.github/workflows/crea-ipa.yml` sia aggiornato.
4. Apri GitHub → Actions → `DVS Music 1.0.3 - iPhone / Radio indipendente e gesture` → `Run workflow`.
5. Quando il workflow è verde, scarica l'artifact `DVS_Music_103_iPhone_IPA_non_firmato`, estrai l'IPA e firmalo con il tuo metodo già funzionante prima di installarlo su iPhone.

## Test

- `tests/radio-v103.swift`: stili, gruppi di artisti, brani bloccati; verifica statica dell'indipendenza dai video consigliati.
- I test già presenti 0.6/0.8/1.0.1/1.0.2 continuano a essere eseguiti.
- I sorgenti Swift del motore sono stati compilati/testati in ambiente Linux. **Non è stato eseguito `xcodebuild` né provato il player su un dispositivo reale** qui; il workflow è il test finale di compilazione iOS.

## Limiti

- L'indice iTunes è usato **soltanto per titoli, artisti e generi**; non vengono usati preview, artwork o file audio Apple. La ricerca degli stream resta affidata a sorgenti YouTube esterne e potrebbe fallire. Controlla compatibilità e condizioni dei servizi esterni.
- La radio non replica l'algoritmo Spotify, non misura audio/BPM e può proporre risultati limitati per artisti poco noti. Last.fm rimane facoltativo.
- La ripresa dopo WhatsApp dipende dalle notifiche iOS e dalla disponibilità effettiva della sessione audio; se WhatsApp mantiene il controllo, iOS può impedire o ritardare il riavvio. Nessuna app di terze parti può garantire il 100% della ripresa in ogni situazione.
