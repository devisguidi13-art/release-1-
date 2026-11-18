# DVS Music 0.7 — installazione da Windows

1. Estrai `DVS_Music_v07_iPhone.zip`.
2. In GitHub apri lo stesso repository usato per la 0.6 e sostituisci i file della root con **il contenuto dello ZIP**; in particolare aggiorna `native-ios/` e `.github/workflows/crea-ipa.yml` (la cartella `.github` può essere nascosta). Non caricare l'intera cartella estratta come sottocartella.
3. Esegui un commit.
4. Vai su **Actions**, scegli **DVS Music 0.7 - iPhone audio nativo**, poi **Run workflow**.
5. Quando è verde, scarica l'artifact `DVS_Music_07_iPhone_IPA_non_firmato` e aprilo per ottenere `DVS_Music_v07_unsigned.ipa`.
6. Firma/installala con lo stesso metodo iPhone già utilizzato per la 0.6. L'IPA non è firmato e non è installabile direttamente.

**Da configurare per migliorare la radio:** in Profilo puoi incollare una chiave API gratuita personale Last.fm. La funzione base rimane senza chiave. Consulta `README_0.7.md`.

**Limite importante:** crossfade reale ed equalizzazione/normalizzazione LUFS non sono ancora attivi a causa del player AVQueuePlayer/streaming remoto. Non è possibile attestare una compilazione riuscita su Xcode o il comportamento iOS prima di eseguire il workflow e testare sul dispositivo.
