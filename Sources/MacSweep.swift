import SwiftUI
import AppKit
import Quartz
import Darwin
import UniformTypeIdentifiers

enum Theme {
    static let background = Color(red: 0.055, green: 0.10, blue: 0.18)
    static let panel = Color(red: 0.085, green: 0.145, blue: 0.24)
    static let accent = Color(red: 0.33, green: 0.69, blue: 0.98)
}

enum Section: String, CaseIterable, Identifiable {
    case overview, largest, downloads, installers, screenshots, duplicates, names, photos, caches, browsers, logs, applications, history, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Panoramica"
        case .largest: return "I file più grandi"
        case .downloads: return "Download"
        case .installers: return "File di installazione"
        case .screenshots: return "Screenshot"
        case .duplicates: return "Duplicati"
        case .names: return "Stesso nome"
        case .photos: return "Serie di foto"
        case .caches: return "Cache applicazioni"
        case .browsers: return "Cache browser"
        case .logs: return "Log applicazioni"
        case .applications: return "Disinstalla applicazioni"
        case .history: return "Cronologia e ripristino"
        case .settings: return "Impostazioni scansione"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "rectangle.grid.2x2"
        case .largest: return "externaldrive"
        case .downloads: return "arrow.down.to.line"
        case .installers: return "shippingbox"
        case .screenshots: return "viewfinder"
        case .duplicates: return "doc.on.doc"
        case .names: return "textformat.abc"
        case .photos: return "photo.stack"
        case .caches: return "internaldrive"
        case .browsers: return "globe"
        case .logs: return "doc.text"
        case .applications: return "app.badge"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "slider.horizontal.3"
        }
    }
    var note: String {
        switch self {
        case .duplicates: return "Contenuto identico verificato con SHA-256. Conserva almeno una copia per gruppo."
        case .names: return "Lo stesso nome non significa lo stesso contenuto. Verifica ogni file."
        case .photos: return "Scatti consecutivi con date EXIF distanti meno di 60 secondi. Non è un confronto visivo; foto senza data EXIF escluse."
        case .caches, .browsers: return "Chiudi le app interessate prima di rimuovere cache. Verranno ricreate al prossimo utilizzo."
        case .logs: return "I log possono essere utili per diagnosticare problemi: verifica la data prima di rimuoverli."
        default: return "Seleziona solo i file da rimuovere. La rimozione li sposta nel Cestino."
        }
    }
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor final class Model: ObservableObject {
    @Published var section: Section = .overview
    @Published var result = ScanResult(files: [], duplicateGroups: [], sameNameGroups: [], photoSeriesGroups: [], issues: [], scannedCount: 0) { didSet { invalidateInventory() } }
    @Published var junk: [FileEntry] = [] { didSet { invalidateInventory() } }
    @Published var roots: [URL] = []
    @Published var exclusions: [URL] = []
    @Published var downloadRoots: [URL] = [] { didSet { invalidateInventory() } }
    @Published var skipSmall = true
    @Published var includeJunk = false
    @Published var includeContainerJunk = false
    @Published var enabledCategories = Set(Section.allCases.filter { ![.overview, .applications, .history, .settings].contains($0) }.map(\.rawValue)) { didSet { invalidateInventory() } }
    @Published var busy = false
    @Published var scanned = 0
    @Published var hasScanned = false
    @Published var didScanJunk = false
    @Published var status = "Scegli una cartella per iniziare. Nessun file è selezionato."
    @Published var selected = Set<String>()
    @Published var query = ""
    @Published var sort = "size"
    @Published var page = 0
    @Published var apps: [AppEntry] = []
    @Published var appQuery = ""
    @Published var chosenApp: AppEntry?
    @Published var related: [RelatedItem] = []
    @Published var uninstallSelection = Set<String>()
    @Published var history: [RemovalRecord] = []
    @Published var pending: [URL] = []
    @Published var showRemoval = false
    @Published var isRemoving = false
    @Published var message: String?
    let store: RemovalStore
    var cancelFlag = CancelFlag()
    var pendingEntries: [String: FileEntry] = [:]
    var appIdentities: [String: FileIdentity] = [:]
    private var categoryCache: [Section: [FileEntry]] = [:]
    private var spaceCache: [Section: String] = [:]
    private var filteredCache: [Section: (query: String, sort: String, selection: Set<String>, files: [FileEntry])] = [:]
    private var selectionCache: (section: Section, ids: Set<String>, files: [FileEntry])?
    private func invalidateInventory() {
        categoryCache.removeAll()
        spaceCache.removeAll()
        filteredCache.removeAll()
        selectionCache = nil
    }
    let perPage = 150

    init() {
        let defaults = UserDefaults.standard
        roots = (defaults.array(forKey: "roots") as? [String] ?? []).map { URL(fileURLWithPath: $0) }
        exclusions = (defaults.array(forKey: "exclusions") as? [String] ?? []).map { URL(fileURLWithPath: $0) }
        downloadRoots = (defaults.array(forKey: "downloadRoots") as? [String] ?? []).map { URL(fileURLWithPath: $0) }
        if defaults.object(forKey: "skipSmall") != nil { skipSmall = defaults.bool(forKey: "skipSmall") }
        if let saved = defaults.array(forKey: "enabledCategories") as? [String] { enabledCategories = Set(saved) }
        // Cache access is opt-in for each launch; no scan runs on application startup.
        store = RemovalStore()
        history = store.records
        apps = ApplicationInventory.list()
        if let i = CommandLine.arguments.firstIndex(of: "--fixture"), CommandLine.arguments.count > i + 1 {
            roots = [URL(fileURLWithPath: CommandLine.arguments[i + 1])]
            skipSmall = false
        }
    }
    func persist() {
        let d = UserDefaults.standard
        d.set(roots.map(\.path), forKey: "roots"); d.set(exclusions.map(\.path), forKey: "exclusions")
        d.set(downloadRoots.map(\.path), forKey: "downloadRoots"); d.set(skipSmall, forKey: "skipSmall")
        d.set(Array(enabledCategories), forKey: "enabledCategories")
    }
    func chooseFolders(for kind: String = "roots") {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = kind == "exclusions"
        p.allowsMultipleSelection = true; p.prompt = "Aggiungi"; p.message = "Scegli le cartelle da esaminare. La scansione non modifica i file."
        guard p.runModal() == .OK else { return }
        switch kind {
        case "exclusions": exclusions = Array(Set(exclusions + p.urls)).sorted { $0.path < $1.path }
        case "downloads": downloadRoots = Array(Set(downloadRoots + p.urls)).sorted { $0.path < $1.path }
        default: roots = Array(Set(roots + p.urls)).sorted { $0.path < $1.path }
        }
        persist()
    }
    func scan() {
        guard !busy else { return }
        guard !roots.isEmpty || includeJunk else { chooseFolders(); return }
        persist(); busy = true; selected = []; scanned = 0; cancelFlag = CancelFlag()
        status = "Scansione in corso…"; hasScanned = false
        let flag = cancelFlag
        let options = ScanOptions(roots: roots + downloadRoots, exclusions: exclusions, minDuplicateSize: skipSmall ? 32768 : 0,
                                  findDuplicates: enabledCategories.contains(Section.duplicates.rawValue),
                                  findSameNames: enabledCategories.contains(Section.names.rawValue),
                                  findPhotoSeries: enabledCategories.contains(Section.photos.rawValue))
        let junkEnabled = includeJunk && [Section.caches, .browsers, .logs].contains { enabledCategories.contains($0.rawValue) }
        let containersEnabled = includeContainerJunk
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = Scanner().scan(options: options, cancelled: { flag.cancelled }, progress: { count in
                DispatchQueue.main.async { self?.scanned = count }
            }, phase: { phase in
                DispatchQueue.main.async { self?.status = phase }
            })
            let beganJunk = junkEnabled && !flag.cancelled
            let cacheResult = beganJunk ? JunkScanner.scan(exclusions: options.exclusions, includeContainers: containersEnabled, cancelled: { flag.cancelled }) : ([], [])
            DispatchQueue.main.async {
                guard let self else { return }
                self.result = found; self.result.issues += cacheResult.1; self.junk = cacheResult.0
                self.scanned = found.scannedCount + cacheResult.0.count; self.busy = false; self.hasScanned = true
                self.didScanJunk = beganJunk
                self.status = flag.cancelled ? "Scansione interrotta. Risultati parziali: \(self.scanned) file." : "Scansione completata: \(found.files.count) file utente, \(cacheResult.0.count) cache/log · \(self.result.issues.count) avvisi."
                self.page = 0
            }
        }
    }
    func files(for category: Section) -> [FileEntry] {
        guard enabledCategories.contains(category.rawValue) else { return [] }
        if let cached = categoryCache[category] { return cached }
        let entries = uncachedFiles(for: category)
        categoryCache[category] = entries
        return entries
    }
    private func uncachedFiles(for category: Section) -> [FileEntry] {
        switch category {
        case .largest: return result.files
        case .downloads:
            return result.files.filter { f in f.url.path.contains("/Downloads/") || downloadRoots.contains { f.url.path.hasPrefix($0.path + "/") } }
        case .installers: return result.files.filter { $0.category == "installers" }
        case .screenshots: return result.files.filter { $0.category == "screenshots" }
        case .duplicates: return grouped(result.duplicateGroups)
        case .names: return grouped(result.sameNameGroups)
        case .photos: return grouped(result.photoSeriesGroups)
        case .caches: return junk.filter { $0.category == "caches" }
        case .browsers: return junk.filter { $0.category == "browsers" }
        case .logs: return junk.filter { $0.category == "logs" }
        default: return []
        }
    }
    /// Candidate sizes are independent of search/selection; categories overlap.
    func sidebarSpace(for category: Section) -> String? {
        guard ![.overview, .applications, .history, .settings].contains(category) else { return nil }
        guard enabledCategories.contains(category.rawValue) else { return "Off" }
        guard hasScanned else { return busy && !isRemoving ? "…" : "—" }
        guard ![.caches, .browsers, .logs].contains(category) || didScanJunk else { return "—" }
        if let cached = spaceCache[category] { return cached }
        let bytes: Int64
        if category == .duplicates {
            // Match extra-copy selection: always retain the first path per group.
            bytes = result.duplicateGroups.reduce(0) { total, group in
                total + group.sorted { $0.url.path < $1.url.path }.dropFirst().reduce(0) { $0 + $1.size }
            }
        } else {
            bytes = files(for: category).reduce(0) { $0 + $1.size }
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        formatter.includesActualByteCount = false
        formatter.zeroPadsFractionDigits = false
        let text = bytes == 0 ? "0 MB" : bytes < 1_000_000 ? "<1 MB" : formatter.string(fromByteCount: bytes)
        spaceCache[category] = text
        return text
    }
    func sidebarSpaceHelp(for category: Section) -> String {
        if [.overview, .applications, .history, .settings].contains(category) { return category.title }
        if !enabledCategories.contains(category.rawValue) { return "Categoria disattivata nelle impostazioni." }
        if !hasScanned { return "Spazio disponibile dopo la scansione." }
        if [.caches, .browsers, .logs].contains(category) && !didScanJunk { return "Categoria non esaminata: abilita la pulizia e ripeti la scansione." }
        return category == .duplicates
            ? "Spazio potenzialmente recuperabile eliminando le copie extra e conservando una copia per gruppo. Le categorie non si sommano."
            : "Dimensione dei file da esaminare: scegli quali rimuovere. Le categorie possono sovrapporsi e non si sommano."
    }
    func grouped(_ groups: [[FileEntry]]) -> [FileEntry] {
        groups.enumerated().flatMap { index, items in items.map { item in var f = item; f.groupID = "Gruppo \(index + 1)"; return f } }
    }
    var filtered: [FileEntry] {
        let orderingSelection = sort == "selected" ? selected : []
        if let cache = filteredCache[section], cache.query == query,
           cache.sort == sort, cache.selection == orderingSelection { return cache.files }
        let all = files(for: section).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.url.path.localizedCaseInsensitiveContains(query) }
        let ordered = all.sorted {
            if [.duplicates, .names, .photos].contains(section), $0.groupID != $1.groupID { return ($0.groupID ?? "").localizedStandardCompare($1.groupID ?? "") == .orderedAscending }
            if sort == "name" { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if sort == "date" { return $0.modified > $1.modified }
            if sort == "dateOld" { return $0.modified < $1.modified }
            if sort == "capture" { return ($0.photoDate ?? $0.modified) > ($1.photoDate ?? $1.modified) }
            if sort == "sizeUp" { return $0.size == $1.size ? $0.id < $1.id : $0.size < $1.size }
            if sort == "kind", $0.url.pathExtension != $1.url.pathExtension { return $0.url.pathExtension.localizedStandardCompare($1.url.pathExtension) == .orderedAscending }
            if sort == "selected", selected.contains($0.id) != selected.contains($1.id) { return selected.contains($0.id) }
            return $0.size == $1.size ? $0.id < $1.id : $0.size > $1.size
        }
        filteredCache[section] = (query, sort, orderingSelection, ordered)
        return ordered
    }
    var visible: [FileEntry] { Array(filtered.dropFirst(page * perPage).prefix(perPage)) }
    var selectedFiles: [FileEntry] {
        guard !selected.isEmpty else { return [] }
        if let cache = selectionCache, cache.section == section, cache.ids == selected { return cache.files }
        let entries = files(for: section).filter { selected.contains($0.id) }
        selectionCache = (section, selected, entries)
        return entries
    }
    func open(_ category: Section) {
        section = category; selected = []; query = ""; page = 0
        if category == .photos { sort = "capture" } else if sort == "capture" { sort = "size" }
    }
    func selectExtraCopies() {
        let visibleIDs = Set(filtered.map(\.id))
        selected = Set(result.duplicateGroups.flatMap { $0.sorted { $0.url.path < $1.url.path }.dropFirst().map(\.id) }).intersection(visibleIDs)
    }
    func prepareRemoval() {
        guard !selectedFiles.isEmpty, !busy else { return }
        let selectedIDs = Set(selectedFiles.map(\.id))
        if section == .duplicates && result.duplicateGroups.contains(where: { Set($0.map(\.id)).isSubset(of: selectedIDs) }) {
            message = "Conserva almeno una copia per ciascun gruppo di duplicati."; return
        }
        pendingEntries = Dictionary(uniqueKeysWithValues: selectedFiles.map { ($0.id, $0) })
        pending = selectedFiles.map(\.url); showRemoval = true
    }
    func removeFiles() {
        showRemoval = false
        guard !busy, !pending.isEmpty else { return }
        // Capture the reviewed scope before yielding. Navigation and live settings
        // must never change which paths this confirmed operation can remove.
        let requests = pending
        let entries = pendingEntries
        let category = section
        let allowedRoots = roots + downloadRoots
        let exactAllowed = [.caches, .browsers, .logs].contains(category) ? requests : []
        let removing = Set(requests.map(\.path))
        let groups = category == .duplicates ? result.duplicateGroups.filter { group in group.contains { removing.contains($0.id) } } : []
        let previousRecordIDs = Set(store.records.map(\.id))
        let flag = CancelFlag()
        cancelFlag = flag
        busy = true; isRemoving = true; scanned = 0
        status = category == .duplicates ? "Verifica del contenuto dei duplicati in corso… Puoi interrompere." : "Verifica dei file selezionati in corso…"
        Task { [self] in
            defer { busy = false; isRemoving = false }
            // Hashing is intentionally detached from the main actor. Only immutable
            // scan snapshots cross this boundary; all journal writes and UI changes
            // stay on the main actor below.
            let verification = await Task.detached(priority: .userInitiated) {
                Self.validateRemoval(requests: requests, entries: entries, groups: groups, flag: flag)
            }.value
            if let problem = verification.error {
                status = "Verifica non riuscita. Nessun file è stato spostato."
                message = problem
                return
            }
            if flag.cancelled {
                status = "Verifica interrotta. Nessun file è stato spostato."
                return
            }
            var errors: [String] = []
            for (index, url) in requests.enumerated() {
                // Let the interface render progress and accept cancellation between
                // individual, durably journaled Trash moves.
                await Task.yield()
                if flag.cancelled { break }
                guard let entry = entries[url.path] else {
                    errors.append("Snapshot mancante: \(url.path). Ripeti la scansione.")
                    break
                }
                if let problem = Self.removalSnapshotError(entry) {
                    errors.append(problem)
                    break
                }
                if let keeper = verification.keepers[url.path], let problem = Self.removalSnapshotError(keeper) {
                    errors.append("La copia da conservare è cambiata. \(problem)")
                    break
                }
                if flag.cancelled { break }
                status = "Spostamento nel Cestino: \(index + 1) di \(requests.count)…"
                // These immediate metadata checks bound staleness after preflight,
                // but do not lock files against concurrent writers. The store also
                // rechecks path/identity before each Foundation Trash operation.
                errors += store.trash(urls: [url], allowedRoots: allowedRoots, exactAllowed: exactAllowed)
                scanned = index + 1
                history = store.records
                if store.loadError != nil { break }
            }
            let moved = Set(store.records.filter { !previousRecordIDs.contains($0.id) && removing.contains($0.originalPath) && $0.trashedPath != nil && !$0.restored }.map(\.originalPath))
            result.files.removeAll { moved.contains($0.id) }
            junk.removeAll { moved.contains($0.id) }
            result.duplicateGroups = result.duplicateGroups.map { $0.filter { !moved.contains($0.id) } }.filter { $0.count > 1 }
            result.sameNameGroups = result.sameNameGroups.map { $0.filter { !moved.contains($0.id) } }.filter { $0.count > 1 }
            result.photoSeriesGroups = result.photoSeriesGroups.map { $0.filter { !moved.contains($0.id) } }.filter { $0.count > 1 }
            history = store.records
            selected = []; pending = []; pendingEntries = [:]; page = 0
            let removalSummary = moved.count == 1 ? "1 elemento spostato nel Cestino." : "\(moved.count) elementi spostati nel Cestino."
            status = flag.cancelled ? "Operazione interrotta. \(removalSummary) Gli altri sono rimasti al loro posto." : removalSummary
            if !errors.isEmpty { message = errors.joined(separator: "\n") }
        }
    }

    nonisolated private static func removalSnapshotError(_ entry: FileEntry) -> String? {
        var current = stat()
        guard lstat(entry.url.path, &current) == 0,
              current.st_mode & S_IFMT == S_IFREG,
              current.st_flags & UInt32(SF_DATALESS) == 0,
              current.st_size == entry.size,
              !RemovalPolicy.hasSymlinkComponent(entry.url) else {
            return "Un file è cambiato o non è più disponibile: \(entry.url.path). Ripeti la scansione."
        }
        let modified = Date(timeIntervalSince1970: Double(current.st_mtimespec.tv_sec) + Double(current.st_mtimespec.tv_nsec) / 1_000_000_000)
        guard abs(modified.timeIntervalSince(entry.modified)) < 0.000_001,
              let device = entry.snapshotDevice, let inode = entry.snapshotInode,
              UInt64(UInt32(bitPattern: current.st_dev)) == device, UInt64(current.st_ino) == inode else {
            return "Il file è stato modificato o sostituito dopo la scansione: \(entry.url.path). Ripeti la scansione."
        }
        return nil
    }

    nonisolated private static func validateRemoval(requests: [URL], entries: [String: FileEntry], groups: [[FileEntry]], flag: CancelFlag) -> (keepers: [String: FileEntry], error: String?) {
        var keepers: [String: FileEntry] = [:]
        for url in requests {
            if flag.cancelled { return (keepers, nil) }
            guard let entry = entries[url.path] else { return (keepers, "Snapshot mancante: \(url.path). Ripeti la scansione.") }
            if let problem = removalSnapshotError(entry) { return (keepers, problem) }
        }
        let removing = Set(requests.map(\.path))
        let scanner = Scanner()
        do {
            for group in groups {
                if flag.cancelled { return (keepers, nil) }
                guard let keeper = group.first(where: { !removing.contains($0.id) }) else {
                    return (keepers, "Conserva almeno una copia per ciascun gruppo di duplicati.")
                }
                guard let digest = try scanner.verifiedDigest(keeper, cancelled: { flag.cancelled }) else {
                    return (keepers, flag.cancelled ? nil : "La copia da conservare non è verificabile. Ripeti la scansione.")
                }
                for item in group where removing.contains(item.id) {
                    if flag.cancelled { return (keepers, nil) }
                    guard let selectedDigest = try scanner.verifiedDigest(item, cancelled: { flag.cancelled }), selectedDigest == digest else {
                        return (keepers, flag.cancelled ? nil : "Il contenuto del gruppo di duplicati è cambiato. Ripeti la scansione.")
                    }
                    keepers[item.url.path] = keeper
                }
            }
        } catch {
            return (keepers, flag.cancelled ? nil : "Verifica dei duplicati non riuscita: \(error.localizedDescription). Ripeti la scansione.")
        }
        return (keepers, nil)
    }
    func chooseApp(_ app: AppEntry) {
        chosenApp = app; related = ApplicationInventory.relatedFiles(for: app); uninstallSelection = [app.url.path]
        appIdentities = Dictionary(uniqueKeysWithValues: ([app.url] + related.map(\.url)).compactMap { url in (try? FileIdentity.read(url)).map { (url.path, $0) } })
    }
    func chooseApplication() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.canChooseFiles = true
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.prompt = "Esamina app"
        guard panel.runModal() == .OK, let url = panel.url, url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url) else { return }
        guard !RemovalPolicy.hasSymlinkComponent(url) else { message = "Seleziona l’app originale, non un collegamento simbolico."; return }
        let running = NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }
        chooseApp(AppEntry(url: url, name: ApplicationInventory.displayName(for: bundle, url: url), bundleID: bundle.bundleIdentifier ?? "", version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "", isRunning: running))
    }
    func uninstall() {
        guard !busy else { return }
        guard let app = chosenApp else { return }
        if app.isRunning || NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.standardizedFileURL == app.url.standardizedFileURL }) {
            message = "Chiudi \(app.name) prima di disinstallarla."; return
        }
        let urls = ([app.url] + related.map(\.url)).filter { uninstallSelection.contains($0.path) }
        guard !urls.isEmpty else { return }
        for url in urls {
            guard let expected = appIdentities[url.path], let current = try? FileIdentity.read(url), current == expected else {
                message = "Un elemento è cambiato durante la verifica: \(url.path). Chiudi e riapri il riepilogo."; return
            }
        }
        var errors: [String] = []
        let ownerIDs: Set<String> = app.bundleID.isEmpty ? [] : [app.bundleID]
        let ownerURLs = [app.url]
        if urls.contains(app.url) {
            let before = Set(store.records.map(\.id))
            errors += store.trash(urls: [app.url], allowedRoots: [], exactAllowed: [app.url], requiredClosedBundleIDs: ownerIDs, requiredClosedAppURLs: ownerURLs)
            guard store.records.contains(where: { !before.contains($0.id) && $0.originalPath == app.url.path && $0.trashedPath != nil }) else {
                history = store.records; message = errors.isEmpty ? "Applicazione non spostata. I dati associati sono stati conservati." : errors.joined(separator: "\n"); return
            }
        }
        let relatedURLs = urls.filter { $0 != app.url }
        errors += store.trash(urls: relatedURLs, allowedRoots: [], exactAllowed: relatedURLs, requiredClosedBundleIDs: ownerIDs, requiredClosedAppURLs: ownerURLs)
        history = store.records; apps = ApplicationInventory.list(); chosenApp = nil
        status = "Operazione conclusa. Controlla la cronologia per gli esiti."
        if !errors.isEmpty { message = errors.joined(separator: "\n") }
    }
    func restore(_ record: RemovalRecord) {
        guard !busy else { return }
        if let error = store.restore(record.id) { message = error }
        else { status = "File ripristinato. Ripeti la scansione per aggiornare i risultati." }
        history = store.records
    }
    static func bytes(_ size: Int64) -> String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

@MainActor final class Preview: NSObject, @preconcurrency QLPreviewPanelDataSource {
    static let shared = Preview()
    var item: NSURL?
    func show(_ url: URL) { item = url as NSURL; let panel = QLPreviewPanel.shared(); panel?.dataSource = self; panel?.reloadData(); panel?.makeKeyAndOrderFront(nil) }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { item == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { item }
}

struct ContentView: View {
    @StateObject var m = Model()
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 235)
            VStack(spacing: 0) {
                header
                Divider()
                Group {
                    switch m.section {
                    case .overview: overview
                    case .settings: settings
                    case .applications: applications
                    case .history: history
                    default: files
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack {
                    if m.busy { ProgressView().controlSize(.small); Text(m.isRemoving ? m.status : "\(m.scanned) file esaminati") }
                    else { Text(m.status).lineLimit(2) }
                    Spacer()
                    Text("MacSweep · 0.1.4").foregroundStyle(.secondary)
                }.font(.caption).padding(.horizontal, 22).frame(height: 48)
            }.background(Theme.panel)
        }
        .background(Theme.background).tint(Theme.accent).preferredColorScheme(.dark)
        .frame(minWidth: 920, minHeight: 620)
        .sheet(isPresented: $m.showRemoval) { removalSheet }
        .sheet(item: $m.chosenApp) { app in uninstallSheet(app) }
        .alert("Esito dell’operazione", isPresented: Binding(get: { m.message != nil }, set: { if !$0 { m.message = nil } })) {
            Button("Chiudi", role: .cancel) { m.message = nil }
        } message: { Text(m.message ?? "") }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) { BrandMark().frame(width: 38, height: 38); Text("MacSweep").font(.title2.bold()) }.padding(.top, 22).padding(.horizontal, 18)
            Text("ESAMINA. SCEGLI. LIBERA.").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary).padding(.horizontal, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sideGroup("FILE UTENTE", [.overview, .largest, .downloads, .installers, .screenshots, .duplicates, .names, .photos])
                    sideGroup("PULIZIA", [.caches, .browsers, .logs])
                    sideGroup("GESTIONE", [.applications, .history, .settings])
                }.padding(.horizontal, 10)
            }
            Text("Nessuna rimozione automatica").font(.caption2).foregroundStyle(.secondary).padding(18)
        }
    }
    func sideGroup(_ title: String, _ categories: [Section]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 14).padding(.leading, 10).padding(.bottom, 6)
            ForEach(categories) { category in
                NavigationSectionButton(category: category, selected: m.section == category, space: m.sidebarSpace(for: category), spaceHelp: m.sidebarSpaceHelp(for: category)) { m.open(category) }
            }
        }
    }
    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) { Text(m.section.title).font(.system(size: 24, weight: .semibold)); Text(m.busy ? m.isRemoving ? "Rimozione dei soli file confermati, con cronologia di ripristino." : "La scansione legge i file, senza modificarli." : "Il controllo resta nelle tue mani.").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if m.busy { Button("Interrompi") { m.cancelFlag.cancel() } }
            else { Button { m.chooseFolders() } label: { Label("Cartelle", systemImage: "folder.badge.plus") }; Button("Scansiona") { m.scan() }.buttonStyle(.borderedProminent) }
        }.padding(22).frame(height: 100)
    }
    var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(m.hasScanned ? "Lo spazio, file per file." : "Fai spazio alle cose che contano.").font(.system(size: 30, weight: .semibold))
                    Text(m.hasScanned ? "\(m.result.files.count) file individuati nelle cartelle scelte. Le categorie possono sovrapporsi: le dimensioni non si sommano." : "Aggiungi una cartella, esamina i risultati e scegli cosa spostare nel Cestino.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !m.hasScanned { Button("Scegli le cartelle da esaminare") { m.chooseFolders() }.padding(.top, 4) }
                }.padding(.vertical, 12)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                    ForEach([Section.largest, .downloads, .installers, .screenshots, .duplicates, .names, .photos, .caches, .browsers, .logs]) { category in
                        Button { m.open(category) } label: {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack { Image(systemName: category.icon).font(.title2).foregroundStyle(Theme.accent); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.secondary) }
                                Text(category.title).font(.headline)
                                Text(!m.enabledCategories.contains(category.rawValue) ? "Disattivata" : !m.hasScanned ? "Da esaminare" : [.caches, .browsers, .logs].contains(category) && !m.didScanJunk ? "Non esaminata" : Model.bytes(m.files(for: category).reduce(0) { $0 + $1.size })).font(.system(size: 25, weight: .medium, design: .rounded))
                                Text("\(m.files(for: category).count) file").font(.caption).foregroundStyle(.secondary)
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).background(Theme.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }
                if !m.result.issues.isEmpty { DisclosureGroup("\(m.result.issues.count) avvisi di scansione") { ForEach(Array(m.result.issues.enumerated()), id: \.offset) { _, text in Text(text).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } } }
            }.padding(26)
        }
    }
    var files: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(m.section.note).font(.caption).foregroundStyle(.secondary)
            if [.caches, .browsers, .logs].contains(m.section) && !m.didScanJunk {
                HStack { Text("La scansione delle cache e dei log richiede una scelta esplicita.").font(.caption); Button("Abilita scansione") { m.includeJunk = true; m.scan() } }
            }
            HStack {
                TextField("Cerca per nome o percorso", text: $m.query).textFieldStyle(.roundedBorder).onChange(of: m.query) { _ in m.page = 0; m.selected = [] }
                if !m.query.isEmpty { Button { m.query = "" } label: { Image(systemName: "xmark.circle.fill") }.help("Cancella ricerca").accessibilityLabel("Cancella ricerca") }
                Picker("Ordina", selection: $m.sort) {
                    if m.section == .photos { Text("Data di scatto").tag("capture") }
                    Text("Dal più grande").tag("size"); Text("Dal più piccolo").tag("sizeUp")
                    Text("Nome").tag("name"); Text("Più recenti").tag("date"); Text("Meno recenti").tag("dateOld")
                    Text("Tipo di file").tag("kind"); Text("Selezionati prima").tag("selected")
                }.frame(width: 210)
            }
            HStack {
                Text(m.filtered.count == 1 ? "1 risultato" : "\(m.filtered.count) risultati").font(.caption); Spacer()
                if m.section == .duplicates { Button("Seleziona copie extra") { m.selectExtraCopies() }.disabled(m.busy) }
                Menu("Seleziona") {
                    Button("Pagina attuale") { m.selected.formUnion(m.visible.map(\.id)) }
                    Button("Tutti i risultati") { m.selected.formUnion(m.filtered.map(\.id)) }
                    Button("Deseleziona tutto") { m.selected = [] }
                }.disabled(m.busy)
            }
            if m.filtered.isEmpty {
                VStack(spacing: 14) { Image(systemName: m.busy ? "magnifyingglass" : "folder").font(.system(size: 36)).foregroundStyle(.secondary); Text(m.busy ? "Ricerca in corso…" : !m.enabledCategories.contains(m.section.rawValue) ? "Categoria disattivata nelle impostazioni" : m.hasScanned ? "Nessun risultato per questa categoria" : "Avvia una scansione per vedere i file"); Text("Le cartelle non accessibili sono indicate negli avvisi.").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(m.visible) { file in
                    HStack(spacing: 12) {
                        Toggle("Seleziona \(file.name)", isOn: Binding(get: { m.selected.contains(file.id) }, set: { if $0 { m.selected.insert(file.id) } else { m.selected.remove(file.id) } })).labelsHidden().toggleStyle(.checkbox).disabled(m.busy)
                        Image(nsImage: FileTypeIcons.image(for: file.url)).resizable().frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(file.name).fontWeight(.medium).lineLimit(1); if let group = file.groupID { Text(group).font(.caption2).foregroundStyle(Theme.accent) } }
                            Text(file.url.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(file.url.path)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) { Text(Model.bytes(file.size)).monospacedDigit(); Text((m.section == .photos ? file.photoDate ?? file.modified : file.modified).formatted(date: .abbreviated, time: m.section == .photos ? .standard : .omitted)).font(.caption2).foregroundStyle(.secondary) }
                        Button { Preview.shared.show(file.url) } label: { Image(systemName: "eye") }.help("Anteprima").accessibilityLabel("Anteprima \(file.name)")
                        Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: { Image(systemName: "folder") }.help("Mostra nel Finder").accessibilityLabel("Mostra \(file.name) nel Finder")
                    }.padding(.vertical, 5).accessibilityElement(children: .contain)
                        .contextMenu {
                            Button("Anteprima") { Preview.shared.show(file.url) }
                            Button("Mostra nel Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                            if let group = file.groupID {
                                let members = m.files(for: m.section).filter { $0.groupID == group }
                                if m.section == .duplicates {
                                    Button("Seleziona copie extra nel gruppo") { m.selected.formUnion(members.sorted { $0.id < $1.id }.dropFirst().map(\.id)) }.disabled(m.busy)
                                }
                                Button("Seleziona il gruppo") { m.selected.formUnion(members.map(\.id)) }.disabled(m.busy)
                                Button("Deseleziona il gruppo") { m.selected.subtract(members.map(\.id)) }.disabled(m.busy)
                            }
                        }
                }.listStyle(.inset)
            }
            HStack {
                Button("Precedente") { m.page -= 1 }.disabled(m.page == 0)
                Text("Pagina \(m.page + 1) di \(max(1, (m.filtered.count + m.perPage - 1) / m.perPage))").font(.caption)
                Button("Successiva") { m.page += 1 }.disabled((m.page + 1) * m.perPage >= m.filtered.count)
                Spacer()
                Text("\(m.selectedFiles.count) \(m.selectedFiles.count == 1 ? "selezionato" : "selezionati") · \(Model.bytes(m.selectedFiles.reduce(0) { $0 + $1.size }))").font(.caption)
                Button("Rivedi rimozione…") { m.prepareRemoval() }.disabled(m.selectedFiles.isEmpty || m.busy).buttonStyle(.borderedProminent)
            }
        }.padding(22)
    }
    var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                folderGroup("Cartelle da esaminare", urls: $m.roots, kind: "roots")
                folderGroup("Eccezioni", urls: $m.exclusions, kind: "exclusions")
                folderGroup("Cartelle Download personalizzate", urls: $m.downloadRoots, kind: "downloads")
                Toggle("Salta duplicati e nomi uguali inferiori a 32 KB", isOn: $m.skipSmall).onChange(of: m.skipSmall) { _ in m.persist() }
                Toggle("Includi cache utente, cache browser e log nella prossima scansione", isOn: $m.includeJunk)
                Toggle("Includi anche cache e log nei container delle app (facoltativo)", isOn: $m.includeContainerJunk).disabled(!m.includeJunk)
                Text("I container richiedono i permessi previsti da macOS. Vengono cercati solo i file nelle sottocartelle Caches e Logs, da verificare singolarmente.").font(.caption).foregroundStyle(.secondary)
                Text("Le modifiche valgono per la prossima scansione. File nascosti, pacchetti, collegamenti simbolici e file cloud non scaricati sono esclusi. La sezione I file più grandi mostra i file esaminati, ordinabili per dimensione.").font(.caption).foregroundStyle(.secondary)
                Text("Categorie da analizzare e mostrare").font(.headline)
                Text("Disattivare duplicati, nomi uguali o serie di foto evita la relativa analisi. L’inventario di base serve alle altre categorie.").font(.caption).foregroundStyle(.secondary)
                ForEach(Section.allCases.filter { ![.overview, .applications, .history, .settings].contains($0) }) { c in
                    Toggle(c.title, isOn: Binding(get: { m.enabledCategories.contains(c.rawValue) }, set: { if $0 { m.enabledCategories.insert(c.rawValue) } else { m.enabledCategories.remove(c.rawValue) }; m.selected = []; m.persist() }))
                }
                Text("Nessun accesso completo al disco viene richiesto automaticamente. Se macOS nega una cartella, il risultato lo segnala.").font(.caption).foregroundStyle(.secondary)
            }.padding(26)
        }.disabled(m.busy)
    }
    func folderGroup(_ title: String, urls: Binding<[URL]>, kind: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title).font(.headline); Spacer(); Button("Aggiungi…") { m.chooseFolders(for: kind) } }
            if urls.wrappedValue.isEmpty { Text("Nessuna cartella aggiunta").font(.caption).foregroundStyle(.secondary) }
            ForEach(urls.wrappedValue, id: \.path) { url in
                HStack { Text(url.path).font(.caption).textSelection(.enabled); Spacer(); Button("Togli") { urls.wrappedValue.removeAll { $0 == url }; m.persist() } }
            }
        }.padding(16).background(Theme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
    var applications: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Funzione aggiuntiva. Cerca i residui con l’identificatore esatto dell’app; i dati condivisi e i servizi di sistema non vengono rimossi.").font(.caption).foregroundStyle(.secondary)
            HStack { TextField("Cerca un’applicazione", text: $m.appQuery).textFieldStyle(.roundedBorder); if !m.appQuery.isEmpty { Button("Cancella") { m.appQuery = "" } }; Button("Scegli app…") { m.chooseApplication() }; Button("Aggiorna elenco") { m.apps = ApplicationInventory.list() } }
            List(m.apps.filter { m.appQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(m.appQuery) }) { app in
                HStack(spacing: 14) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 4) { Text(app.name).font(.headline); Text("\(app.version) · \(app.bundleID)").font(.caption).foregroundStyle(.secondary); Text(app.url.path).font(.caption2).foregroundStyle(.secondary) }
                    Spacer()
                    if app.isRunning { Text("In esecuzione").font(.caption) }
                    Button("Esamina…") { m.chooseApp(app) }.disabled(m.busy)
                }.padding(.vertical, 6).accessibilityElement(children: .contain)
            }.listStyle(.inset)
        }.padding(22)
    }
    var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Il ripristino funziona finché l’elemento registrato è ancora nel Cestino. Non sovrascrive file già presenti nella posizione originale.").font(.caption).foregroundStyle(.secondary)
            if m.history.isEmpty { Text("Nessuna rimozione effettuata con MacSweep.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                List(m.history.reversed()) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 5) { Text(URL(fileURLWithPath: record.originalPath).lastPathComponent).font(.headline); Text(record.originalPath).font(.caption2).textSelection(.enabled); Text(record.date.formatted()).font(.caption2).foregroundStyle(.secondary); if let error = record.error { Text(error).font(.caption).foregroundStyle(.orange) } }
                        Spacer()
                        if record.restored { Text("Ripristinato").font(.caption) }
                        else if record.trashedPath != nil { Button("Ripristina") { m.restore(record) }.disabled(m.busy) }
                        else { Text("Verifica esito").font(.caption) }
                    }.padding(.vertical, 6).accessibilityElement(children: .contain)
                }
            }
        }.padding(22)
    }
    var removalSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(m.pending.count == 1 ? "Spostare 1 elemento nel Cestino?" : "Spostare \(m.pending.count) elementi nel Cestino?").font(.title2.bold())
            Text("Controlla i percorsi. Puoi provare a ripristinarli dalla cronologia finché restano nel Cestino.").foregroundStyle(.secondary)
            List(m.pending, id: \.path) { Text($0.path).font(.caption).textSelection(.enabled) }.frame(height: 240)
            HStack { Button("Annulla", role: .cancel) { m.showRemoval = false }.keyboardShortcut(.cancelAction); Spacer(); Button("Sposta nel Cestino", role: .destructive) { m.removeFiles() } }
        }.padding(26).frame(width: 650)
    }
    func uninstallSheet(_ app: AppEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Disinstalla \(app.name)").font(.title2.bold())
            Text("L’app e i residui selezionati saranno spostati nel Cestino. I dati dell’app possono contenere documenti: sono esclusi finché non li selezioni.").font(.caption).foregroundStyle(.secondary)
            if app.isRunning { Label("Chiudi l’app prima di procedere.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            List {
                uninstallRow(app.url, reason: "Applicazione")
                ForEach(m.related) { item in uninstallRow(item.url, reason: item.reason) }
            }.frame(height: 300)
            Text("Il rilevamento è conservativo: container, estensioni, servizi e file con nomi diversi possono restare sul Mac.").font(.caption).foregroundStyle(.secondary)
            HStack { Button("Annulla", role: .cancel) { m.chosenApp = nil }.keyboardShortcut(.cancelAction); Spacer(); Button("Sposta selezionati nel Cestino", role: .destructive) { m.uninstall() }.disabled(app.isRunning || m.uninstallSelection.isEmpty) }
        }.padding(26).frame(width: 680)
    }
    func uninstallRow(_ url: URL, reason: String) -> some View {
        Toggle(isOn: Binding(get: { m.uninstallSelection.contains(url.path) }, set: { if $0 { m.uninstallSelection.insert(url.path) } else { m.uninstallSelection.remove(url.path) } })) {
            VStack(alignment: .leading, spacing: 4) { Text(reason).font(.headline); Text(url.path).font(.caption2).textSelection(.enabled) }
        }.toggleStyle(.checkbox).padding(.vertical, 5)
    }
}

struct BrandMark: View {
    private static let image: NSImage? = {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: "BrandIcon", withExtension: "png", subdirectory: "Resources")
        #else
        let url = Bundle.main.url(forResource: "BrandIcon", withExtension: "png")
        #endif
        return url.flatMap { NSImage(contentsOf: $0) }
    }()

    var body: some View {
        Group {
            if let image = Self.image { Image(nsImage: image).resizable().interpolation(.high).scaledToFit() }
            else { Image(systemName: "sparkle.magnifyingglass").resizable().scaledToFit() }
        }.accessibilityHidden(true)
    }
}

@MainActor enum FileTypeIcons {
    private static let cache = NSCache<NSString, NSImage>()
    static func image(for url: URL) -> NSImage {
        let ext = url.pathExtension.lowercased()
        if let image = cache.object(forKey: ext as NSString) { return image }
        let image = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        cache.countLimit = 128
        cache.setObject(image, forKey: ext as NSString)
        return image
    }
}

struct NavigationSectionButton: View {
    let category: Section
    let selected: Bool
    let space: String?
    let spaceHelp: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Label(category.title, systemImage: category.icon)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let space {
                    Text(space)
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .fixedSize()
                }
            }
                .help(spaceHelp)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 9)
                // The hit target includes the entire row, including clear space.
                .contentShape(Rectangle())
                .background(selected ? Theme.accent.opacity(0.22) : hovered ? Color.white.opacity(0.07) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct MacSweepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("MacSweep") { ContentView() }.defaultSize(width: 1180, height: 780)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
