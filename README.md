# MacSweep 0.1 — prima implementazione indipendente

Progetto principale: `/Users/mariolone/Documents/progettiPersonali/MacSweep`.
Applicazione compilata: `build/MacSweep.app`.

## Avvio
Puoi estrarre `build/MacSweep.app.zip` oppure aprire `build/MacSweep.app`, poi aggiungi le cartelle da esaminare e premi **Scansiona**.
Non parte alcuna scansione automatica. Scegli pochi file di prova prima di usare
la rimozione sui tuoi dati. Nessun accesso completo al disco viene concesso
automaticamente. Non servono REA, Java o Ghidra per usare MacSweep.

1. **Cartelle**: scegli una o più cartelle; **Impostazioni scansione** permette
   di aggiungere eccezioni e cartelle Download personalizzate.
2. Apri una categoria, cerca per nome/percorso, ordina e seleziona i file.
3. **Rivedi rimozione…** mostra i percorsi prima di **Sposta nel Cestino**.
4. **Cronologia e ripristino** consente di recuperare gli elementi ancora nel
   Cestino. Non viene mai svuotato il Cestino.
5. **Disinstalla applicazioni** permette di esaminare un’app installata o
   selezionarne una con **Scegli app…**. I residui non sono preselezionati.

## Funzioni implementate
- Panoramica, file ordinati per dimensione, download, installer DMG/PKG/MPKG/ISO,
  screenshot con metadati Spotlight o euristica del nome.
- Duplicati verificati con SHA-256 a lettura progressiva, raggruppati prima per
  dimensione; selezione delle copie extra con almeno un elemento conservato.
- File con nome esatto uguale, separati dal confronto del contenuto.
- Serie di immagini con date EXIF: scatti consecutivi distanti meno di 60 secondi,
  anche in cartelle diverse; nessun ripiego sulla data di creazione del file.
- Cache utente in Library/Caches, identificazione euristica delle sottocartelle
  browser, log in Library/Logs; scansione da abilitare esplicitamente.
- Opzione separata per i soli suffissi Data/Library/Caches e Data/Library/Logs
  dei container delle app, con segnalazione dei percorsi non accessibili.
- Anteprima Quick Look, mostra nel Finder, ricerca, ordinamento, pagine da 150
  file, cancellazione della scansione e risultati parziali segnalati.
- Disinstallazione conservativa: app e candidati con bundle ID esatto nelle
  preferenze, cache, Application Support, HTTPStorages, WebKit, Logs e stato
  salvato. Blocco delle app in esecuzione e ricontrollo prima di ogni elemento.
- Cronologia persistente con intenti registrati prima delle operazioni e
  ripristino che rifiuta sovrascritture e identità dei file cambiate.

## Limiti dichiarati
Questa versione non è una copia certificata identica di Cleaner-App. Il report
`REVERSE-ENGINEERING.md` distingue evidenze, inferenze e regole di progetto.
Gli algoritmi proprietari possono restituire gruppi diversi. Le serie di foto
sono temporali: non riconoscono somiglianza visiva o qualità delle immagini.
Il parser ISOBMFF dell’originale non è ricreato: alcune foto HEIC/container senza
EXIF riconosciuto possono restare fuori dai gruppi.
Cache dei container non abilitate o non accessibili, servizi, estensioni, login
item, dati condivisi e file associati con nomi diversi possono non essere trovati. La rimozione di
un pacchetto .app non sostituisce l’uninstaller del produttore per driver o
servizi privilegiati. Non sono implementati acquisti, pubblicità o telemetria.

I file nascosti, i collegamenti simbolici, i pacchetti e i file cloud non ancora
scaricati sono esclusi dalla scansione dei documenti. Le dimensioni sono
logiche, non una promessa di spazio fisico recuperato su APFS. Le categorie si
sovrappongono: non sommarle. Permessi negati possono rendere la scansione parziale.
La cronologia è privata e locale in `~/Library/Application Support/MacSweep`.
Se il processo termina esattamente tra lo spostamento nel Cestino e il salvataggio
della destinazione, può servire il recupero manuale dal Cestino. Le operazioni
Foundation conservano un piccolo margine di corsa tra controllo e spostamento.

## Compilazione e test
Richiede un Mac Apple Silicon e Command Line Tools con Swift 6.2.1 (usato in
modalità linguaggio Swift 5); non serve Xcode completo. Il binario consegnato è
ARM64, compilato con l’SDK del Mac di lavoro; altri sistemi non sono collaudati.

```sh
bash build.sh
bash test.sh
```

`Package.swift` consente anche di aprire i sorgenti come progetto Swift Package.
Gli script qui sopra producono e collaudano il bundle `.app` consegnato.

La firma è ad hoc locale, non Developer ID/notarizzazione. Non è una release
pubblica certificata. Il codice usa solo framework macOS: nessuna dipendenza
runtime di terze parti. Gli strumenti di reverse engineering sono in `work/`
e non fanno parte dell’app o del pacchetto sorgente distribuibile.

## Risultati del collaudo
60 controlli automatici su dati di prova, più prove reali di rimozione e
ripristino dei soli file generati dal progetto. Dettagli in VERIFICATION.md.
L’app pronta e i sorgenti sono separati dagli strumenti di reverse engineering:
la cartella work/tools può essere archiviata quando non serve più all’analisi,
senza impedire l’uso di MacSweep. Non cancellarla se vuoi proseguire con Ghidra.

La versione 0.1.6 conserva la cronologia precedente e registra i nuovi aggiornamenti
in `removal-history.json.events`, accanto a `removal-history.json`. Conservare
entrambi per mantenere tutta la cronologia; le versioni precedenti non leggono
il nuovo registro. Ogni intento e ogni esito continuano a essere sincronizzati
su disco singolarmente.

## Panoramica e cache — 0.2.0
La panoramica distingue File utente e File inutili. La prima apertura di File
inutili (o di una categoria cache/log) avvia una scansione di sola lettura,
senza aspettare l'analisi dei duplicati. I risultati si possono aggiornare con
Aggiorna scansione cache. Le categorie spuntate vengono selezionate nella
revisione; solo la successiva conferma sposta i file nel Cestino.

Oltre a Library/Caches e Library/Logs, vengono cercate le sole cache GPUCache,
Service Worker/CacheStorage e Service Worker/ScriptCache dei profili Chrome.
Cookie, password, cronologia e Local Storage non vengono enumerati. Media
Spotify e mappe GeoServices restano esclusi dalla pulizia standard. Gli avvisi
segnalano permessi mancanti o risultati parziali; non equivalgono a zero byte.
