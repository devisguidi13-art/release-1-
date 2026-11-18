# DVS Music 1.0.1 — Revisione e correzione dei bug

## Correzioni incluse

1. **Stop alla fine del brano:** quando imposti questa opzione, la lista di `AVPlayerItem` futuri già preparati viene rimossa, impedendo l'avanzamento automatico non desiderato. Se annulli il timer, il prefetch viene ripristinato.
2. **Timer a minuti più robusto:** oltre al time observer musicale, un controllo a intervalli verifica l'ora di scadenza anche quando la riproduzione è in buffering. In background i timer iOS non sono hard real-time: verificare su dispositivo.
3. **Blocchi persistenti delle copie:** `Non consigliarmi questo brano` memorizza anche la chiave canonica artista+titolo, oltre all'ID specifico YouTube. Filtra i caricamenti dello stesso brano da canali diversi. Nessuna cancellazione delle vecchie chiavi `UserDefaults`.
4. **Metadati YouTube:** titoli con trattini tipografici `–` o `—` vengono normalizzati come il trattino semplice; migliorano il riconoscimento dei brani raccomandati.
5. **Race condition prefetch:** un vecchio task di risoluzione URL non può più resettare lo stato di caricamento di una coda nuova.
6. **Race condition radio:** disabilitare/riabilitare la radio non consente ai risultati obsoleti di entrare nella nuova coda.
7. **Race condition ricerca:** una ricerca più lenta non sovrascrive una ricerca più recente.
8. **Ripetizioni ridotte:** vengono escluse anche le copie canoniche dei brani ascoltati di recente. La radio ora cerca nuovi brani partendo dal brano attuale e non dall'ultimo candidato in fondo alla coda.
9. **Statistiche più fedeli:** il contatore dei secondi non avanza quando `AVPlayer` dichiara buffering anziché riproduzione.
10. **Cache Last.fm:** le risposte sono separate per chiave API attiva.
11. **Build ripetibile:** `YouTubeKit` fissato a `0.4.10` invece di accettare versioni nuove potenzialmente incompatibili; bundle `1.0.1 (11)` per aggiornamento su dispositivo.
12. **Robustezza locale:** rimosso un force-unwrap in un calcolo di cronologia.

## Verifica effettuata

- Integrità del file ZIP e struttura del progetto verificata.
- Compilazione ed esecuzione su Linux dei test Swift basati su Foundation: coda intelligente, metadati, skip, Smart Shuffle, filtri e salvataggi. Aggiunti test per dash Unicode e blocchi canonici persistenti.
- Parsing di **tutti** i file Swift (`swiftc -frontend -parse`).
- Test TypeScript per ricerca video e logica di coda con npm.
- Controllo `Info.plist`, dimensione icona e configurazioni YAML.

## Ancora da verificare con iPhone/GitHub

- Compilazione completa in Xcode (i framework Apple non sono disponibili su Linux).
- Interazione tra `AVQueuePlayer`, notifiche fine brano, cambio coda durante buffering e sessioni audio durante il riconoscimento vocale.
- Comportamento effettivo del timer e consumo batteria a schermo spento.
- Disponibilità in tempo reale dei nodi Invidious, di Last.fm e delle URL stream e stabilità delle sorgenti.
- Durata delle pause nel passaggio brano: senza iPhone e rete reale non si può misurare né garantire “istantaneo”.
- Compatibilità/permessi d'uso delle fonti audio: restano responsabilità da verificare prima della distribuzione.

## Installazione

Caricare tutto il contenuto estratto dello ZIP (inclusa `.github`) nel repository GitHub già usato. Actions → **DVS Music 1.0.1 - iPhone Premium / Verifica bug** → Run workflow. Dopo il build verde, scaricare l'artifact IPA non firmato e firmare/installare con il metodo già usato. Eseguire un backup locale dei preferiti prima di sostituire un'app sideloaded.
