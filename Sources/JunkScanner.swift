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
        // Cleaner-App's inspected review omits these large media/map stores.
        // Keep offline media/map content out of standard junk recommendations.
        let retainedStores = ["Library/Caches/com.spotify.client", "Library/Caches/GeoServices"].map { home.appendingPathComponent($0) }
        func excluded(_ url: URL) -> Bool { (exclusions + retainedStores).contains { RemovalPolicy.contains(url, in: $0) } }
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
        // Runtime observation in Cleaner-App confirms these Chrome cache roots.
        // Profiles are enumerated only one level deep; no history, cookies,
        // passwords, Local Storage, IndexedDB or arbitrary support data is walked.
        let chrome = home.appendingPathComponent("Library/Application Support/Google/Chrome")
        if admittedDirectory(chrome) {
            do {
                for profile in try fm.contentsOfDirectory(at: chrome, includingPropertiesForKeys: [.isDirectoryKey]) {
                    if cancelled() { break }
                    guard profile.lastPathComponent == "Default" || profile.lastPathComponent.hasPrefix("Profile "), admittedDirectory(profile) else { continue }
                    for suffix in ["GPUCache", "Service Worker/CacheStorage", "Service Worker/ScriptCache"] {
                        roots.append((profile.appendingPathComponent(suffix), "browsers"))
                    }
                }
            } catch { report("Impossibile esaminare le cache di Chrome: \(error.localizedDescription)") }
        }
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

        var hitLimit = false
        func walk(_ directory: URL, descriptor: Int32, kind: String) {
            guard let stream = fdopendir(descriptor) else { Darwin.close(descriptor); report("Impossibile esaminare \(directory.path)"); return }
            defer { closedir(stream) }
            while !cancelled() && !hitLimit {
                errno = 0
                guard let next = readdir(stream) else {
                    if errno != 0 { report("Impossibile leggere \(directory.path): \(String(cString: strerror(errno)))") }
                    break
                }
                let name = withUnsafePointer(to: &next.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(next.pointee.d_namlen) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                let url = directory.appendingPathComponent(name)
                if excluded(url) { continue }
                var file = stat()
                guard fstatat(dirfd(stream), name, &file, AT_SYMLINK_NOFOLLOW) == 0 else { report("Impossibile leggere \(url.path): \(String(cString: strerror(errno)))"); continue }
                let type = file.st_mode & S_IFMT
                if type == S_IFLNK { continue }
                if file.st_flags & UInt32(SF_DATALESS) != 0 { report("File cloud non scaricato, ignorato: \(url.path)"); continue }
                if type == S_IFDIR {
                    do { if try url.resourceValues(forKeys: [.isPackageKey]).isPackage == true { continue } }
                    catch { report("Impossibile leggere \(url.path): \(error.localizedDescription)"); continue }
                    let child = openat(dirfd(stream), name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    guard child >= 0 else { report("Impossibile aprire \(url.path): \(String(cString: strerror(errno)))"); continue }
                    var opened = stat()
                    guard fstat(child, &opened) == 0, opened.st_ino == file.st_ino, opened.st_dev == file.st_dev,
                          opened.st_flags & UInt32(SF_DATALESS) == 0 else { Darwin.close(child); report("Cartella cambiata, ignorata: \(url.path)"); continue }
                    walk(url, descriptor: child, kind: kind)
                } else if type == S_IFREG && visited.insert(url.path).inserted {
                    let modified = Date(timeIntervalSince1970: Double(file.st_mtimespec.tv_sec) + Double(file.st_mtimespec.tv_nsec) / 1_000_000_000)
                    let created = Date(timeIntervalSince1970: Double(file.st_birthtimespec.tv_sec) + Double(file.st_birthtimespec.tv_nsec) / 1_000_000_000)
                    entries.append(FileEntry(id: url.path, url: url, name: name, size: Int64(file.st_size), modified: modified, created: created,
                                             category: kind == "caches" && isBrowserCache(url) ? "browsers" : kind,
                                             snapshotDevice: UInt64(UInt32(bitPattern: file.st_dev)), snapshotInode: UInt64(file.st_ino)))
                    if entries.count >= cap { hitLimit = true }
                }
            }
        }
        for (root, kind) in roots {
            if cancelled() || hitLimit { break }
            guard admittedDirectory(root) else { continue }
            let descriptor = openDirectory(root)
            if descriptor >= 0 { walk(root, descriptor: descriptor, kind: kind) }
            else { report("Impossibile aprire \(root.path): \(String(cString: strerror(errno)))") }
        }
        if hitLimit {
            let warning = "Limite di 200.000 file cache/log raggiunto: risultati parziali."
            if issues.count < 100 { issues.append(warning) } else { issues[99] = warning }
        }
        return (entries, issues)
    }

    private static func openDirectory(_ url: URL) -> Int32 {
        var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return -1 }
        for component in url.pathComponents where component != "/" {
            let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let failure = errno
            Darwin.close(fd)
            guard next >= 0 else { errno = failure; return -1 }
            fd = next
        }
        return fd
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
