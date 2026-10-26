import Foundation
import AppKit
import Darwin

struct AppEntry: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    let isRunning: Bool
}

struct RelatedItem: Identifiable {
    var id: String { url.path }
    let url: URL
    let reason: String
    let requiresReview: Bool
}

@MainActor
enum ApplicationInventory {
    static func displayName(for bundle: Bundle, url: URL) -> String {
        let names = [bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                     bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
                     url.deletingPathExtension().lastPathComponent]
        return names.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? "Applicazione"
    }
    static func list(roots: [URL] = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]) -> [AppEntry] {
        let fm = FileManager.default
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.standardizedFileURL.path })
        var seen = Set<String>()
        var result: [AppEntry] = []
        for root in roots {
            guard root.standardizedFileURL.resolvingSymlinksInPath() == root.standardizedFileURL else { continue }
            guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { continue }
            while let url = iterator.nextObject() as? URL {
                let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                if values?.isSymbolicLink == true { iterator.skipDescendants(); continue }
                guard url.pathExtension.lowercased() == "app", values?.isDirectory == true else { continue }
                iterator.skipDescendants()
                guard !url.path.hasPrefix("/System/"), seen.insert(url.path).inserted,
                      let bundle = Bundle(url: url) else { continue }
                result.append(AppEntry(url: url, name: displayName(for: bundle, url: url), bundleID: bundle.bundleIdentifier ?? "", version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "", isRunning: running.contains(url.standardizedFileURL.path)))
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func relatedFiles(for app: AppEntry, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [RelatedItem] {
        let identifier = app.bundleID
        // A bundle identifier is data, never a path or a fuzzy name pattern.
        guard !identifier.isEmpty, identifier != ".", identifier != "..", !identifier.contains("/"), !identifier.contains("\\"), !identifier.contains("\0") else { return [] }
        let candidates: [(String, String)] = [
            ("Preferences/\(identifier).plist", "Preferenze con identificatore esatto"),
            ("Caches/\(identifier)", "Cache con identificatore esatto"),
            ("Application Support/\(identifier)", "Dati dell’app: verifica prima di rimuoverli"),
            ("HTTPStorages/\(identifier)", "Archivio HTTP con identificatore esatto"),
            ("WebKit/\(identifier)", "Dati WebKit con identificatore esatto"),
            ("Logs/\(identifier)", "Log con identificatore esatto"),
            ("Saved Application State/\(identifier).savedState", "Stato salvato con identificatore esatto")
        ]
        return candidates.compactMap { relative, reason in
            let url = home.appendingPathComponent("Library").appendingPathComponent(relative).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path), !RemovalPolicy.hasSymlinkComponent(url) else { return nil }
            return RelatedItem(url: url, reason: reason, requiresReview: true)
        }
    }
}

struct FileIdentity: Codable, Equatable {
    let device: UInt64
    let inode: UInt64
    static func read(_ url: URL) throws -> FileIdentity {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let device = a[.systemNumber] as? NSNumber, let inode = a[.systemFileNumber] as? NSNumber else {
            throw NSError(domain: "MacSweep", code: 1, userInfo: [NSLocalizedDescriptionKey: "Identità del file non disponibile"])
        }
        return FileIdentity(device: device.uint64Value, inode: inode.uint64Value)
    }
}

struct RemovalRecord: Codable, Identifiable {
    let id: UUID
    let originalPath: String
    var trashedPath: String?
    let date: Date
    var restored: Bool
    var error: String?
    var identity: FileIdentity?
}

enum RemovalPolicy {
    static func contains(_ child: URL, in root: URL) -> Bool {
        let c = child.standardizedFileURL.path, r = root.standardizedFileURL.path
        return c == r || c.hasPrefix(r == "/" ? "/" : r + "/")
    }

    static func hasSymlinkComponent(_ url: URL) -> Bool {
        var current = URL(fileURLWithPath: "/")
        for part in url.standardizedFileURL.pathComponents.dropFirst() {
            current.appendPathComponent(part)
            if (try? FileManager.default.attributesOfItem(atPath: current.path)[.type] as? FileAttributeType) == .typeSymbolicLink { return true }
        }
        return false
    }

    static func validationError(url: URL, allowedRoots: [URL], exactAllowed: [URL] = []) -> String? {
        let url = url.standardizedFileURL
        let path = url.path
        if !url.isFileURL || hasSymlinkComponent(url) { return "Collegamento simbolico o percorso non locale: operazione rifiutata." }
        let protected = ["/", "/System", "/Library", "/usr", "/bin", "/sbin", "/private", "/dev", "/Volumes", "/Network", "/cores"]
        if protected.contains(where: { $0 == path || ($0 != "/" && path.hasPrefix($0 + "/")) }) { return "Percorso di sistema protetto." }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let library = home.appendingPathComponent("Library")
        let libraryRoots = ["Caches", "Logs", "Preferences", "Application Support", "HTTPStorages", "WebKit", "Saved Application State", "Containers", "Group Containers"].map { library.appendingPathComponent($0).path }
        let critical = [home.path, library.path, "/Applications", "/Users", home.appendingPathComponent("Applications").path, home.appendingPathComponent(".Trash").path] + libraryRoots
        if critical.contains(path) || contains(url, in: home.appendingPathComponent(".Trash")) { return "Cartella essenziale o Cestino: operazione rifiutata." }
        if contains(url, in: library.appendingPathComponent("Group Containers")) { return "I contenitori condivisi possono appartenere a più applicazioni: operazione rifiutata." }
        // Exact capabilities authorize app bundles and the individually reviewed related artifacts.
        let exact = exactAllowed.contains { $0.standardizedFileURL == url && !hasSymlinkComponent($0) }
        if contains(url, in: URL(fileURLWithPath: "/Applications")) {
            guard exact, url.pathExtension.lowercased() == "app" else { return "Le applicazioni richiedono una selezione esplicita del pacchetto .app." }
        }
        if contains(url, in: library), !exact {
            let safeLibraries = ["Caches", "Logs"].map { library.appendingPathComponent($0) }
            guard safeLibraries.contains(where: { contains(url, in: $0) && url != $0 }) else { return "I dati della Libreria richiedono una verifica individuale." }
        }
        let withinRoot = allowedRoots.contains { root in
            let root = root.standardizedFileURL
            return root != url && !hasSymlinkComponent(root) && contains(url, in: root)
        }
        guard exact || withinRoot else { return "Il file non appartiene alle cartelle autorizzate." }
        if allowedRoots.contains(where: { $0.standardizedFileURL != url && contains($0, in: url) }) { return "La cartella contiene una radice di scansione: operazione rifiutata." }
        guard FileManager.default.fileExists(atPath: path) else { return "Il file non esiste più." }
        return nil
    }
}

@MainActor
final class RemovalStore {
    private(set) var records: [RemovalRecord] = []
    private(set) var loadError: String?
    let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacSweep/removal-history.json")
        guard FileManager.default.fileExists(atPath: self.storageURL.path) else { return }
        do {
            guard !RemovalPolicy.hasSymlinkComponent(self.storageURL) else { throw CocoaError(.fileReadNoPermission) }
            records = try JSONDecoder().decode([RemovalRecord].self, from: Data(contentsOf: self.storageURL))
        } catch { loadError = "Cronologia non leggibile. Nessun file verrà spostato: \(error.localizedDescription)" }
    }

    private func persist() throws {
        if let loadError { throw NSError(domain: "MacSweep", code: 2, userInfo: [NSLocalizedDescriptionKey: loadError]) }
        guard !RemovalPolicy.hasSymlinkComponent(storageURL) else { throw CocoaError(.fileWriteNoPermission) }
        let directory = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(records).write(to: storageURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
        let handle = try FileHandle(forWritingTo: storageURL)
        try handle.synchronize()
        try handle.close()
        let fd = Darwin.open(directory.path, O_RDONLY)
        if fd >= 0 { defer { Darwin.close(fd) }; if fsync(fd) != 0 { throw CocoaError(.fileWriteUnknown) } }
    }

    static func validationError(url: URL, allowedRoots: [URL], exactAllowed: [URL] = []) -> String? {
        RemovalPolicy.validationError(url: url, allowedRoots: allowedRoots, exactAllowed: exactAllowed)
    }

    func trash(urls: [URL], allowedRoots: [URL], exactAllowed: [URL] = [], requiredClosedBundleIDs: Set<String> = [], requiredClosedAppURLs: [URL] = []) -> [String] {
        if let loadError { return [loadError] }
        var errors: [String] = []
        var seen = Set<String>()
        for url in urls.map({ $0.standardizedFileURL }).sorted(by: { $0.path.count < $1.path.count }) {
            guard seen.insert(url.path).inserted else { continue }
            if let app = runningOwner(bundleIDs: requiredClosedBundleIDs, appURLs: requiredClosedAppURLs) {
                errors.append("\(app): l’app è in esecuzione. Operazione interrotta; i file rimanenti non sono stati spostati.")
                break
            }
            if let problem = Self.validationError(url: url, allowedRoots: allowedRoots, exactAllowed: exactAllowed) { errors.append("\(url.lastPathComponent): \(problem)"); continue }
            let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL }
            if running.contains(where: { RemovalPolicy.contains($0, in: url) }) { errors.append("\(url.lastPathComponent): chiudi prima l’applicazione."); continue }
            do {
                let identity = try FileIdentity.read(url)
                let record = RemovalRecord(id: UUID(), originalPath: url.path, trashedPath: nil, date: Date(), restored: false, error: "Operazione avviata; destinazione non ancora confermata.", identity: identity)
                records.append(record)
                let index = records.count - 1
                do { try persist() } catch { records.removeLast(); throw error }
                do {
                    guard Self.validationError(url: url, allowedRoots: allowedRoots, exactAllowed: exactAllowed) == nil, try FileIdentity.read(url) == identity else { throw CocoaError(.fileReadUnknown) }
                    // Recheck after journal I/O too: the owner can relaunch while the
                    // filesystem synchronizes the intent record. This is still a
                    // best-effort guard, not a lock preventing other app launches.
                    if let app = runningOwner(bundleIDs: requiredClosedBundleIDs, appURLs: requiredClosedAppURLs) {
                        records[index].error = "\(app): l’app è stata avviata. Il file non è stato spostato."
                        try persist()
                        errors.append(records[index].error!)
                        break
                    }
                    var destination: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
                    records[index].trashedPath = destination?.path
                    records[index].error = destination == nil ? "Spostato nel Cestino, ma percorso di ripristino non disponibile." : nil
                    if let dest = destination as URL? { records[index].identity = try FileIdentity.read(dest) }
                    do { try persist() } catch {
                        // In-memory destination is retained; no second move is attempted.
                        records[index].error = "Spostato nel Cestino; salvataggio della cronologia fallito. Percorso: \(destination?.path ?? "sconosciuto"). \(error.localizedDescription)"
                        errors.append(records[index].error!)
                        loadError = "Cronologia non sincronizzata: riavvia dopo aver verificato i file nel Cestino."
                        break
                    }
                } catch {
                    records[index].error = error.localizedDescription
                    try? persist()
                    errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            } catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        return errors
    }

    private func runningOwner(bundleIDs: Set<String>, appURLs: [URL]) -> String? {
        guard !bundleIDs.isEmpty || !appURLs.isEmpty else { return nil }
        let paths = Set(appURLs.map { $0.standardizedFileURL.path })
        return NSWorkspace.shared.runningApplications.first { app in
            if let identifier = app.bundleIdentifier, !identifier.isEmpty, bundleIDs.contains(identifier) { return true }
            return app.bundleURL.map { paths.contains($0.standardizedFileURL.path) } ?? false
        }.map { $0.localizedName ?? $0.bundleIdentifier ?? "Applicazione" }
    }

    func restore(_ id: UUID) -> String? {
        if let loadError { return loadError }
        guard let index = records.firstIndex(where: { $0.id == id }), !records[index].restored, let trashed = records[index].trashedPath else { return "Nessun percorso di ripristino verificato. Controlla il Cestino manualmente." }
        let source = URL(fileURLWithPath: trashed), destination = URL(fileURLWithPath: records[index].originalPath)
        guard !RemovalPolicy.hasSymlinkComponent(source), !RemovalPolicy.hasSymlinkComponent(destination.deletingLastPathComponent()) else { return "Percorso cambiato o collegamento simbolico: ripristino rifiutato." }
        guard !FileManager.default.fileExists(atPath: destination.path) else { return "Esiste già un elemento nel percorso originale. Nessun file è stato sovrascritto." }
        guard FileManager.default.fileExists(atPath: destination.deletingLastPathComponent().path) else { return "La cartella originale non esiste più. Ripristina il file manualmente dal Cestino." }
        do {
            guard let identity = records[index].identity, try FileIdentity.read(source) == identity else { return "Il file nel Cestino è cambiato: ripristino rifiutato." }
            records[index].error = "Ripristino avviato; completamento non ancora confermato."
            try persist()
            try FileManager.default.moveItem(at: source, to: destination)
            records[index].restored = true
            records[index].error = nil
            do { try persist() } catch {
                loadError = "File ripristinato, ma cronologia non sincronizzata: \(error.localizedDescription)"
                return loadError
            }
            return nil
        } catch {
            records[index].error = error.localizedDescription
            try? persist()
            return error.localizedDescription
        }
    }
}
