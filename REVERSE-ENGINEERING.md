# Cleaner-App → MacSweep: guida e stato del reverse engineering

Analisi del 26 ottobre 2026. Obiettivo: ricreare le funzioni di ricerca e pulizia
richieste in un’app indipendente, con disinstallazione aggiuntiva. Questa prima
versione funziona, ma **la parità completa con Cleaner-App non è certificata**.

## Cosa è stato realmente analizzato

Cleaner-App 9.7, build 934, identificatore `com.nektony.App-Cleaner`.
SHA-256 dell’eseguibile universale installato:
`dd6c874b264f92f7fdf3e2fd432af914741849ea40c4906378a84bf9310faed8`.
Il digest è rimasto uguale a fine analisi: l’eseguibile installato non è stato
modificato. È stata creata una copia ARM64 per Ghidra, digest
`bd31b4f0845e8fe1e413c5658d75b14d2adac366e33e9cc655ef9723990cadd4`.

Sono stati usati la skill Reverse Engineer Anything versione 49, REA 6.8.0,
Ghidra 12.1.4 e OpenJDK 21.0.11 già presente in Eclipse. L’archivio Ghidra è stato
scaricato dalla release ufficiale e verificato con SHA-256
`ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db`.
Il componente nativo ARM è stato compilato dai sorgenti ufficiali inclusi.

La skill è stata applicata dal bundle locale: non sono stati modificati i file
di configurazione globali di Codex e non occorre riavviarlo. Nessun acquisto,
Hopper o altra licenza commerciale è stato attivato.

## Metodo seguito

1. Identità del binario, struttura del pacchetto e risorse localizzate.
2. Osservazione delle schermate dell’app installata e delle impostazioni, senza
   attivarne alcuna rimozione.
3. Simboli e stringhe come indizi, separati dalle prove degli algoritmi.
4. Importazione della copia ARM in Ghidra tramite sessione locale temporanea REA.
5. Analisi mirata di funzioni, riferimenti, metadati Swift e istruzioni ARM.
6. Implementazione originale in Swift, poi test automatici e prove reali su
   file generati esclusivamente per il collaudo.

L’importazione iniziale ha superato il limite di 330 secondi. Dopo il controllo
della sessione e l’aumento documentato del budget, il secondo tentativo è
riuscito. Nessun analizzatore è stato disabilitato. Alcuni avvisi/errori interni
di Ghidra e chiamate indirette limitano comunque le conclusioni su singole
funzioni. Il pseudocodice non è il sorgente originale e non dimostra da solo il
comportamento durante l’esecuzione.

La sessione è stata esportata e chiusa correttamente. In
`work/cleaner-evidence/rea-native-evidence.json` del progetto principale sono
conservati 70 record; `cleaner-analysis.snapshot.json` conserva lo snapshot.
Questi conteggi non significano che ogni funzione dell’app sia stata verificata.
Gli strumenti di analisi e la copia del binario restano in `work/`, separati dal
programma MacSweep distribuito.

## Risultati e differenze

| Funzione | Evidenza dell’originale | MacSweep e limiti |
|---|---|---|
| Panoramica e categorie | Osservate nella navigazione | Implementate con risultati reali; categorie sovrapponibili |
| File grandi | Osservati anche file inferiori a 1 MB | Tutti i file indicizzati, ordinabili per dimensione; eventuale limite top-N originale non ricostruito |
| Download | Navigazione e cartelle personalizzate nelle impostazioni | Cartelle Download e percorsi aggiunti dall’utente |
| Installer | Predicato DMG/PKG osservato nel binario | DMG/PKG, più ISO/MPKG come estensione indipendente |
| Screenshot | Predicato Spotlight e attributo di cattura presenti | Spotlight più euristica del nome; lista originale di prefissi/estensioni non completamente ricostruita |
| Duplicati | Percorsi di hash parziale e completo verificati | SHA-256 completo e controllo dei file cambiati; non è una copia del motore proprietario |
| Nomi uguali | Categoria e soglia configurabile osservate | Raggruppamento per nome esatto, distinto dal contenuto |
| Serie di foto | Soglia stretta <60 secondi, concatenazione consecutiva, date parser e filtro attributi recuperati | Regole recuperate applicate; fallback ISOBMFF originale non implementato |
| Cache e log | Categorie osservate, costruzione di percorsi verificata | Inventario conservativo da rivedere; regole originali di esclusione/età/quick-clean non interamente ricostruite |
| Cronologia/ripristino | Risorse e messaggi dell’originale | Journal persistente, Trash e ripristino collaudati su fixture |
| Disinstallazione | Non osservata nella navigazione di questa app; risorse condivise non bastano a provarla | Aggiunta richiesta dall’utente, conservativa; servizi/driver/container condivisi esclusi |

### Duplicati: cosa sappiamo e cosa no

`FileSeparator::calculateHashForItem:fullHash:` a `0x100013be4` richiama
`RSFileReader::processItem:deep:skipMetadata:`. Il reader distingue il percorso
completo `hashforFile:` da quello parziale
`hashforFilePartly:withSize:hashPartBlockLength:forFilesGreatherThan:forkToRead:`.
La configurazione usa una dimensione di blocco e una soglia pari a tre blocchi.
Per dimensione logica zero, questo helper costruisce un’impronta dal nome;
l’uso completo di questa regola nel modello duplicati non è stato dimostrato.

Evidenze principali:
`ev_7a2745ce3f039c15f79c4d90a38994a7a5261c4f246f3a923179ed1579665ccc`,
`ev_b6b2975a844d7d34aa30cf1de033a43e94ec7fd9ee775371b09cf524cd6871a3`,
`ev_7722a4915d096500942894347263fe13241fc4b59988870084851d640949a854`,
`ev_c4cd58b43227c0b91fbfa9fe1cdbd85f68aa6fcf261cb11ea0e9cf6880eb2af2`.

Le risorse dicono “32 KB”. Nel percorso delle impostazioni sono stati individuati
un puntatore a una costante `0x8800` (34816) e uno a memoria non inizializzata;
non è stato ricostruito l’intero flusso fino al confronto di ammissione. Perciò
non viene dichiarata una soglia originale certa di 32768 byte. MacSweep usa
32768 come scelta esplicita, disattivabile, non come fatto recuperato.
Evidenze: `ev_901976f829a8e60e1f8f7dcc6896726032487133d116cbc40d6f4cdc986ecaa3`,
`ev_ff91d25594f50ac4f9e39333c630eccb53e56a6bcf2fdec98ea5bfc8f4fc654d`.

### Foto: regola recuperata

Il confronto a `0x100118ac0`, corroborato con istruzioni ARM, usa una differenza
strettamente inferiore a 60.0 secondi. Il builder a `0x100194cf4` confronta
coppie consecutive nell’ordine delle date. Una catena può dunque durare più di
un minuto complessivo. Lo stadio esaminato non impone la stessa cartella.
Vengono scartati gruppi con meno di due file e gruppi in cui tutti i file hanno
uguale dimensione logica e uguale data parser. Non è un test di somiglianza visiva.

L’originale prova un parser EXIF e poi un parser ISOBMFF. MacSweep legge EXIF
DateTimeOriginal tramite ImageIO e non inventa date dalla creazione del file:
immagini senza metadati riconosciuti restano escluse. Il supporto ISO BMFF e
l’intera selezione iniziale dei formati sono ancora da confrontare.
Vedi `Evidence/photo-grouping-findings.md` per indirizzi e tutte le evidenze.

### Cache: confine di sicurezza e fedeltà

`FUN_1000bc8e8` costruisce i suffissi `Data/Library/Caches` e
`Data/Library/Logs` sotto i container. Le chiamate indirette non permettono di
provare tutte le regole originali di rimozione. La presenza di un percorso nel
binario non autorizza a considerare eliminabili i suoi dati. Non sono state
copiate regole per LocalStorage o altri archivi persistenti da semplici stringhe.
Vedi `Evidence/cache-and-screenshot-findings.md`.

## Come proseguire il confronto fedele

- Per ogni regola ancora aperta, costruire prima una fixture con un esito
  misurabile: file uguali/differenti, soglie 32767/32768/34816, immagini a
  distanza 59/60/61 secondi e formati EXIF/HEIC senza EXIF.
- Confrontare gli insiemi di percorsi restituiti, non solo i totali in GB.
- Per confrontare la scansione dell’originale sui soli dati di prova, concordare
  un cambio temporaneo delle cartelle nelle sue impostazioni e il loro ripristino;
  questa analisi non ha modificato le cartelle di scansione di Cleaner-App.
- Seguire il modello `DuplicatesSearcherImpl` dal descrittore Swift fino al
  criterio finale prima di dichiarare identica la semantica degli hash.
- Per cache e browser, ricostruire i filtri reali e fare prove solo su profili
  usa-e-getta, prima di ampliare le rimozioni.
- Aggiungere i casi verificati ai test del progetto; non promuovere un’ipotesi a
  comportamento dell’originale senza nuove evidenze.

Le fonti decompilate dell’originale non sono state inserite nell’app. Nome,
codice, controlli e asset di MacSweep sono indipendenti. Nessuna protezione di
licenza dell’originale è stata modificata.
