# Verifiche — 26 ottobre 2026

## Controlli automatici
- Scanner: 27 controlli su fixture, inclusi contenuto uguale/nomi diversi,
  nomi uguali/contenuto diverso, esclusioni, soglia, radici sovrapposte,
  pacchetti, symlink e cancellazione.
- Identità: confronto di inode/device e test di sostituzione con dimensione e
  data conservate; rifiuto del cambio di un antenato in symlink durante l’hash.
- Rimozione: 13 controlli su policy, confini di percorso, protezioni, cronologia
  danneggiata e rifiuto delle operazioni quando non può essere registrata.
- Cache/log: 20 controlli su home fittizia; opt-in dei container, nessun
  accesso agli altri dati, bundle ID terminanti in .app, esclusioni,
  cancellazione e identità dei file.
- Audit statico delle regole UI: zero rilievi; non prova da solo accessibilità
  o correttezza delle operazioni.

## Collaudo reale dell’interfaccia
Eseguito su Mac Apple Silicon, macOS 26.2, in italiano, con i soli file generati
in Tests/Fixture. Nessun file personale e nessuna app realmente installata
sono stati rimossi.

1. Stato iniziale: nessun risultato e nessuna rimozione automatica.
2. Scansione: 8 file, 2 gruppi duplicati, 1 gruppo con nome uguale e contenuto
   diverso, installer fittizio, screenshot PNG. La prima implementazione raggruppava anche immagini senza
   EXIF: è stata successivamente allineata alla regola recuperata.
   Sono state poi aggiunte quattro foto JPEG con date EXIF controllate.
3. La selezione di tutte le copie in Duplicati è stata rifiutata.
4. Selezione copie extra: 2 file spostati nel Cestino, registrati e ripristinati
   dalla cronologia; presenza al percorso originale verificata sul filesystem.
5. Scelta di App di prova.app tramite pannello nativo, spostamento del pacchetto
   fittizio nel Cestino e ripristino dalla cronologia: riusciti.
6. Copia da conservare modificata dopo la scansione, preservando dimensione e
   data: rimozione dell’altra copia rifiutata per contenuto cambiato. Fixture
   ripristinata successivamente.

## Copertura ancora da completare
Non sono stati rimossi cache reali, dati personali o software reale; nessun
collaudo di servizi privilegiati. Non è stata certificata l’equivalenza delle
regole proprietarie né l’accessibilità con lettore di schermo. Versioni macOS
diverse dal Mac di lavoro, Intel, notarizzazione e distribuzione pubblica non
sono collaudate. Le prove end-to-end sopra sono osservazioni manuali ripetibili,
non una suite UI automatizzata. I test non eliminano il margine TOCTOU delle API
Foundation, documentato nel README.

## Collaudo della versione finale
- 60 controlli automatici complessivi superati: 27 scanner, 13 rimozione,
  20 cache/log.
- Quattro JPEG EXIF di prova: tre scatti a intervalli di 30 secondi formano
  un gruppo; lo scatto successivo distante esattamente 60 secondi ne resta
  fuori. Le date di scatto sono mostrate nella lista.
- Ricerca senza risultati, cancellazione della ricerca e menu nativo di
  ordinamento verificati.
- Rimozione asincrona del singolo duplicato di prova e ripristino riusciti
  nella versione finale aperta dalla cartella progettiPersonali/MacSweep.
- Cartella di prova tolta dalle impostazioni e filtro dei file piccoli
  ripristinato; cache/container restano disattivati inizialmente.
- Archivio dell’app estratto in una cartella locale temporanea e firma ad hoc
  verificata con codesign --deep --strict. Non è notarizzazione Apple.
