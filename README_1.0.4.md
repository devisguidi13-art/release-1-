# DVS Music 1.0.4 — Categorie dinamiche (tutti i generi)

## Novità principali

- **Tutte le categorie** dell'interfaccia condividono la stessa logica; incluse 20 categorie: Trap italiana, Trap internazionale, Hip hop/Rap, Indie, Pop, R&B/Soul, Rock, Techno, Reggaeton, Lo-fi, Chill, Dance/EDM, House, Latin, Jazz, Metal, Classica, Country, K-Pop e Afrobeats.
- **Novità**: uscite degli ultimi **90 giorni**, ordinate per data decrescente (album e brani). Dopo 90 giorni escono automaticamente dalle Novità al successivo aggiornamento, ma possono restare in classifica.
- **Classifica DVS**: brani e album ordinati utilizzando, ove disponibili, le classifiche pubbliche Apple RSS; completamento da iTunes Search API e, quando configurata, classifica per tag Last.fm. **Non è una classifica ufficiale per singolo genere**, e gli ultimi risultati di ricerca non garantiscono l'ordine di popolarità. Dati reali, nessuna graduatoria inventata.
- **Aggiornamenti**: cache locale per **12 ore** per categoria. L'apertura di un genere verifica la freschezza. Mentre DVS rimane aperta, l'app controlla gradualmente tutti i generi; il tasto aggiorna e il pull-to-refresh forzano l'aggiornamento. **iOS non garantisce aggiornamenti a orari fissi quando l'app è sospesa**.
- **Offline**: ultimo catalogo valido salvato in locale. Non sovrascrive un catalogo pieno con una risposta vuota.
- **Riproduzione**: premendo un brano, DVS cerca l'identità artista+titolo nella sorgente esistente e solo dopo riproduce; gli album aprono la tracklist iTunes.
- **Alternativa SoundCloud**: icona dedicata accanto ai risultati che cerca quella pubblicazione nella piattaforma ufficiale; apre SoundCloud, senza aggirare limitazioni o estrarre audio. Per un'integrazione nativa completa di SoundCloud occorrono l'abilitazione API e una traccia abilitata allo streaming verso app terze. Alcuni artisti mainstream non sono disponibili senza abbonamento o licenza.

## Accesso ai contenuti

1. Apri **Cerca** e tocca uno qualsiasi dei 20 generi.
2. Tocca **Novità** o **Classifica DVS**. Premi una canzone per farla cercare e riprodurre da DVS.
3. Se è un album, aprilo per scegliere il singolo brano. Se non è disponibile su DVS, premi l'icona di SoundCloud o il collegamento Apple Music.
4. Trascina verso il basso o premi il simbolo Aggiorna per ricaricare la categoria.

## Sorgenti, costi e limiti

- Servizi per il **catalogo**: Apple Marketing Tools RSS e iTunes Search API (senza chiave personale), usati per dati delle pubblicazioni, classifiche pubbliche e metadati. L'accesso rimane soggetto a termini e limiti dei fornitori.
- **Sorgente audio alternativa**: link di ricerca SoundCloud ufficiale (non streaming interno automatico). Non è possibile promettere un secondo streaming completamente gratuito per tutta la musica commerciale internazionale.
- Il motore audio principale della 1.0.3 resta invariato; la presente versione non introduce estrazione audio da provider commerciali senza autorizzazione.
- I sottogeneri come Trap e Lo-fi sono identificati mediante etichette e/o artisti-seme; non garantiscono completezza. Gli album più recenti non sono necessariamente pubblicati su tutti i feed.
- Le playlist non vengono cancellate o sostituite: il ricambio automatico riguarda **l'elenco mostrato** nelle categorie.
- Per un'app destinata a distribuzione pubblica, verificare le condizioni d'uso dei feed, dei loghi e delle copertine Apple.

## Installazione manuale GitHub Actions

1. Estrai lo ZIP e carica nel tuo repository GitHub i file e le cartelle **alla radice**, non dentro un'altra cartella.
2. Sovrascrivi i file esistenti, mantenendo `.github/workflows/crea-ipa.yml`, `native-ios/DVSMusic`, `tests` e gli altri percorsi.
3. Apri **Actions → DVS Music 1.0.4 - iPhone / Classifiche dinamiche per tutti i generi → Run workflow**.
4. Se la compilazione è verde scarica `DVS_Music_104_iPhone_IPA_non_firmato`; per installare su iPhone devi firmare correttamente l'IPA con il sistema già usato per la 1.0.3.

## Controlli effettuati

- Test offline di filtri, ordinamento release, deduplicazione, cache e URL SoundCloud.
- Test dei motori precedenti native-core, 0.8, 1.0.1, 1.0.2 e 1.0.3.
- Parse di tutti i sorgenti Swift. **La compilazione Xcode completa e il funzionamento live dei feed vanno verificati sul tuo workflow GitHub/macOS**, non eseguiti qui.
