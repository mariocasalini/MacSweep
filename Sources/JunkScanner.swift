import Foundation
import Darwin

/// Read-only inventory of user-reviewed cleanup candidates. The optional
/// container suffixes were observed in Cleaner-App's static path constructor;
/// that evidence does NOT establish its automatic deletion eligibility rules.
/// No discovery here authorizes removal, and no application data outside the
/// exact cache/log roots (including Group Containers) is enumerated.
enum JunkScanner {
    static func scan(exclusions: [URL], includeContainers: Bool = false,
                     home: URL = FileManager.default.homeDirectoryForCurrentUser,
                     cancelled: () -> Bool) -> ([FileEntry], [String]) {
        let fm = FileManager.default
        let home = home.standardizedFileURL
        let exclusions = exclusions.map(\.standardizedFileURL)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
                                        .creationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        var entries: [FileEntry] = []
        var issues: [String] = []
        var visited = Set<String>()
        let cap = 200_000
        func report(_ text: String) { if issues.count < 100 { issues.append(text) } }
        func excluded(_ url: URL) -> Bool { exclusions.contains { RemovalPolicy.contains(url, in: $0) } }
        func state(_ url: URL) -> stat? {
            var value = stat()
            if lstat(url.path, &value) == 0 { return value }
            if errno != ENOENT { report("Impossibile leggere \(url.path): \(String(cString: strerror(errno)))") }
            return nil
        }
        func admittedDirectory(_ url: URL, allowContainerPackageMarker: Bool = false) -> Bool {
            if cancelled() || excluded(url) { return false }
            guard let value = state(url) else { return false }
            guard value.st_mode & S_IFMT == S_IFDIR, !RemovalPolicy.hasSymlinkComponent(url) else {
                report("Percorso non sicuro o non cartella, ignorato: \(url.path)"); return false
            }
            guard value.st_flags & UInt32(SF_DATALESS) == 0 else {
                report("Cartella cloud non scaricata, ignorata: \(url.path)"); return false
            }
            do {
                let resource = try url.resourceValues(forKeys: keys)
                if resource.isPackage == true && !allowContainerPackageMarker { return false }
                if resource.isUbiquitousItem == true && resource.ubiquitousItemDownloadingStatus == .notDownloaded {
                    report("Cartella cloud non scaricata, ignorata: \(url.path)"); return false
                }
            } catch { report("Impossibile leggere \(url.path): \(error.localizedDescription)"); return false }
            return true
        }

        var roots: [(URL, String)] = [(home.appendingPathComponent("Library/Caches"), "caches"),
                                     (home.appendingPathComponent("Library/Logs"), "logs")]
        if includeContainers && !cancelled() {
            let containers = home.appendingPathComponent("Library/Containers")
            if admittedDirectory(containers) {
                do {
                    // Only list immediate container names, then construct the two
                    // verified suffixes. Never walk Documents, Preferences,
                    // LocalStorage, Application Support or arbitrary Data children.
                    for container in try fm.contentsOfDirectory(at: containers, includingPropertiesForKeys: Array(keys)).sorted(by: { $0.path < $1.path }) {
                        if cancelled() { break }
                        // In this one known slot the name is a bundle identifier,
                        // which can legitimately end in ".app". Do not mistake
                        // its package marker for permission to walk app contents:
                        // only the two exact Data/Library suffixes are admitted.
                        if admittedDirectory(container, allowContainerPackageMarker: true) {
                            roots.append((container.appendingPathComponent("Data/Library/Caches"), "caches"))
                            roots.append((container.appendingPathComponent("Data/Library/Logs"), "logs"))
                        }
                    }
                } catch { report("Impossibile elencare \(containers.path): \(error.localizedDescription)") }
            }
        }

        for (root, kind) in roots {
            if cancelled() { break }
            guard admittedDirectory(root) else { continue }
            guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys),
                                               options: [.skipsPackageDescendants], errorHandler: { url, error in
                report("Impossibile leggere \(url.path): \(error.localizedDescription)"); return true
            }) else { report("Impossibile esaminare \(root.path)"); continue }
            for case let candidate as URL in iterator {
                if cancelled() { return (entries, issues) }
                let url = candidate.standardizedFileURL
                guard let file = state(url) else { continue }
                let isDirectory = file.st_mode & S_IFMT == S_IFDIR
                if excluded(url) {
                    // skipDescendants on a regular file can skip its next sibling.
                    if isDirectory { iterator.skipDescendants() }
                    continue
                }
                guard file.st_mode & S_IFMT != S_IFLNK else { continue }
                do {
                    let resource = try url.resourceValues(forKeys: keys)
                    if resource.isPackage == true { continue } // enumerator already skips descendants
                    if file.st_flags & UInt32(SF_DATALESS) != 0 ||
                        (resource.isUbiquitousItem == true && resource.ubiquitousItemDownloadingStatus == .notDownloaded) {
                        if isDirectory { iterator.skipDescendants() }
                        report("File cloud non scaricato, ignorato: \(url.path)"); continue
                    }
                    guard file.st_mode & S_IFMT == S_IFREG,
                          !RemovalPolicy.hasSymlinkComponent(url), visited.insert(url.path).inserted else { continue }
                    let modified = Date(timeIntervalSince1970: Double(file.st_mtimespec.tv_sec) + Double(file.st_mtimespec.tv_nsec) / 1_000_000_000)
                    entries.append(FileEntry(id: url.path, url: url, name: url.lastPathComponent, size: Int64(file.st_size),
                                             modified: modified, created: resource.creationDate ?? modified,
                                             category: kind == "caches" && isBrowserCache(url) ? "browsers" : kind,
                                             snapshotDevice: UInt64(UInt32(bitPattern: file.st_dev)), snapshotInode: UInt64(file.st_ino)))
                    if entries.count >= cap {
                        let warning = "Limite di 200.000 file cache/log raggiunto: risultati parziali."
                        if issues.count < 100 { issues.append(warning) } else { issues[99] = warning }
                        return (entries, issues)
                    }
                } catch { report("Impossibile leggere \(url.path): \(error.localizedDescription)") }
            }
        }
        return (entries, issues)
    }

    private static func isBrowserCache(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let knownIDs: Set<String> = ["com.apple.safari", "com.apple.safaritechnologypreview", "com.google.chrome",
                                     "org.chromium.chromium", "org.mozilla.firefox", "com.microsoft.edgemac",
                                     "com.brave.browser", "com.operasoftware.opera", "com.vivaldi.vivaldi"]
        return url.pathComponents.contains { knownIDs.contains($0.lowercased()) } ||
            ["/google/chrome/", "/chromium/", "/firefox/", "/microsoft edge/", "/bravesoftware/"].contains(where: path.contains)
    }
}
