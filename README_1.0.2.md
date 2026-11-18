# DVS Music 1.0.2 — Brani ufficiali e copertine reali

## Cosa è cambiato

- **Ricerca e radio ufficiale-prima (senza impostazioni):** DVS effettua la ricerca normale e una ricerca indirizzata ai canali di distribuzione musicale. Assegna priorità ai caricamenti pertinenti su canali `Artista - Topic`, quindi ai video VEVO riconoscibili, poi agli altri risultati. Se non trova un caricamento ufficiale plausibile, mostra anche i ricaricamenti di terzi.
- **Doppioni:** la stessa registrazione caricata da due canali diversi viene ordinata privilegiando la fonte musicale più plausibile, senza falsi badge di verifica.
- **Cover reale nel player:** il titolo e l'artista vengono confrontati con MusicBrainz. Se corrispondono, la foto dell'album/singolo è recuperata dal Cover Art Archive e mostrata nel player, mini-player, libreria e schermata di blocco; altrimenti resta la thumbnail YouTube.
- **Velocità:** le copertine vengono recuperate *in modo asincrono*, senza bloccare il motore di riproduzione o la ricerca dei brani successivi. I link delle cover vengono salvati in cache sul telefono; la ricerca MusicBrainz è limitata a circa una richiesta per secondo.

## Limiti e correttezza

I nomi Topic/VEVO e i titoli dei video sono soltanto indizi: i risultati delle istanze di ricerca non consentono di verificare al 100% il canale ufficiale. Le miniature e copertine non sono garantite per ogni brano. L'app non genera copertine con IA, non usa iTunes/Apple Music artwork al di fuori delle relative condizioni promozionali e non aggiunge abbonamenti.

Le istanze Invidious pubbliche possono fallire o non restituire tutti i risultati; la riproduzione tramite sorgenti YouTube non ufficiali non è garantita e deve rispettare i termini applicabili. Anche il tempo reale di passaggio tra i brani va verificato su iPhone.

## Come compilare

Estrarre lo ZIP direttamente **nella root del repository GitHub esistente**, sostituendo i file. Aprire `Actions → DVS Music 1.0.2 - iPhone / Brani ufficiali e copertine reali → Run workflow`. La compilazione crea un IPA non firmato negli Artifacts.

## Verifiche disponibili

- `tests/official-cover-v102.swift` — test offline ordinamento Topic/VEVO/ricaricamenti, match delle copertine e manifest CAA.
- `tests/intelligence-v10.swift` — regressioni motore 1.0.1 adattate alla preferenza ufficiale.
- Test 0.8 per libreria e 0.6 per ricerca/coda, controllo sintattico Swift.
- Necessaria compilazione Xcode (GitHub Actions) e verifica funzionale su iPhone.
