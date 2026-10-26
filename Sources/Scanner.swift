import Foundation
import CryptoKit
import ImageIO
import CoreServices
import Darwin

struct ScanOptions {
    var roots: [URL]
    var exclusions: [URL] = []
    var minDuplicateSize: Int64 = 32_768
    var photoSeriesInterval: TimeInterval = 60
    var findDuplicates = true
    var findSameNames = true
    var findPhotoSeries = true
}

struct FileEntry: Identifiable, Hashable {
    var id: String
    var url: URL
    var name: String
    var size: Int64
    var modified: Date
    var created: Date
    var category: String
    var groupID: String? = nil
    var isDirectory: Bool = false
    var snapshotDevice: UInt64? = nil
    var snapshotInode: UInt64? = nil
    var photoDate: Date? = nil
}

struct ScanResult {
    var files: [FileEntry]
    var duplicateGroups: [[FileEntry]]
    var sameNameGroups: [[FileEntry]]
    var photoSeriesGroups: [[FileEntry]]
    var issues: [String]
    var scannedCount: Int
}

/// Read-only scanner. It never changes permissions, downloads cloud placeholders,
/// follows symbolic links, enters application packages, or deletes anything.
final class Scanner {
    private let manager = FileManager.default
    private let imageExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "gif", "webp"]
    private let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso"]
    private let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
        .fileSizeKey, .contentModificationDateKey, .creationDateKey,
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
    ]

    func scan(options: ScanOptions, cancelled: () -> Bool = { false }, progress: (Int) -> Void = { _ in }) -> ScanResult {
        var files: [FileEntry] = []
        var issues: [String] = []
        var visited = Set<String>()
        var scannedCount = 0
        func issue(_ value: String) {
            if issues.count < 100 { issues.append(value) }
        }
        let excluded = options.exclusions.map { $0.standardizedFileURL.path }
        let protected = ["/System", "/Library", "/private", "/dev", "/proc", "/Volumes", "/usr", "/bin", "/sbin", "/Applications", "/Network", "/cores",
                         manager.homeDirectoryForCurrentUser.appendingPathComponent("Library").path]
        func contains(_ path: String, in roots: [String]) -> Bool {
            roots.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
        func excludedPath(_ path: String) -> Bool { contains(path, in: excluded) || contains(path, in: protected) }
        let roots = options.roots.map(\.standardizedFileURL).sorted { $0.path < $1.path }
        var admittedRoots: [String] = []
        for root in roots {
            if cancelled() { break }
            let path = root.path
            if contains(path, in: admittedRoots) || excludedPath(path) { continue }
            do {
                let values = try root.resourceValues(forKeys: keys)
                guard values.isDirectory == true, values.isSymbolicLink != true,
                      root.resolvingSymlinksInPath().path == path, values.isPackage != true else {
                    issue("Cartella ignorata: collegamento, pacchetto o percorso non valido: \(path)")
                    continue
                }
                admittedRoots.append(path)
            } catch {
                issue("Impossibile leggere \(path): \(error.localizedDescription)")
                continue
            }
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: Array(keys),
                                                       options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                       errorHandler: { url, error in
                issue("Impossibile leggere \(url.path): \(error.localizedDescription)")
                return true
            }) else {
                issue("Impossibile esaminare la cartella: \(path)")
                continue
            }
            for case let url as URL in enumerator {
                if cancelled() { break }
                let path = url.standardizedFileURL.path
                if excludedPath(path) {
                    if (try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map({ $0.isDirectory == true && $0.isSymbolicLink != true }) == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                do {
                    let value = try url.resourceValues(forKeys: keys)
                    if value.isSymbolicLink == true || value.isPackage == true {
                        // The enumerator already skips both. Calling skipDescendants
                        // on a link/package can incorrectly skip the next sibling.
                        continue
                    }
                    var fileState = stat()
                    guard lstat(path, &fileState) == 0 else {
                        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                    }
                    let isDataless = fileState.st_flags & UInt32(SF_DATALESS) != 0
                    if isDataless || (value.isRegularFile == true && value.isUbiquitousItem == true && value.ubiquitousItemDownloadingStatus == .notDownloaded) {
                        if value.isDirectory == true { enumerator.skipDescendants() }
                        issue("File iCloud non scaricato, ignorato: \(path)")
                        continue
                    }
                    guard value.isRegularFile == true, fileState.st_mode & S_IFMT == S_IFREG,
                          url.resolvingSymlinksInPath().path == path,
                          visited.insert(path).inserted else { continue }
                    let size = Int64(fileState.st_size)
                    let name = url.lastPathComponent
                    let ext = url.pathExtension.lowercased()
                    var category = "largest"
                    if root.lastPathComponent == "Downloads" || path.contains("/Downloads/") { category = "downloads" }
                    if installerExtensions.contains(ext) { category = "installers" }
                    if isScreenshot(url) { category = "screenshots" }
                    files.append(FileEntry(id: path, url: url, name: name, size: size,
                                           modified: modificationDate(fileState),
                                           created: value.creationDate ?? value.contentModificationDate ?? .distantPast,
                                           category: category,
                                           snapshotDevice: UInt64(UInt32(bitPattern: fileState.st_dev)),
                                           snapshotInode: UInt64(fileState.st_ino)))
                    scannedCount += 1
                    if scannedCount % 100 == 0 { progress(scannedCount) }
                } catch { issue("Impossibile leggere \(path): \(error.localizedDescription)") }
            }
        }
        progress(scannedCount)
        let candidates = files.filter { $0.size >= max(0, options.minDuplicateSize) }
        var duplicates: [[FileEntry]] = []
        for (_, sameSize) in Dictionary(grouping: candidates, by: \.size).sorted(by: { $0.key < $1.key }) where options.findDuplicates && sameSize.count > 1 {
            if cancelled() { break }
            var hashes: [String: [FileEntry]] = [:]
            for file in sameSize {
                if cancelled() { break }
                do {
                    if let digest = try hash(file, cancelled: cancelled) { hashes[digest, default: []].append(file) }
                } catch { issue("Confronto non completato per \(file.url.path): \(error.localizedDescription)") }
            }
            // A cancelled group must not be presented as a completed comparison.
            if cancelled() { break }
            duplicates += hashes.values.filter { $0.count > 1 }.map { group in
                let ordered = group.sorted { $0.url.path < $1.url.path }
                return ordered.map { item in var item = item; item.groupID = "duplicate:\(ordered[0].id)"; return item }
            }
        }
        let sameNames: [[FileEntry]] = !options.findSameNames ? [] : Dictionary(grouping: candidates, by: \.name).values.filter { $0.count > 1 }.map { group -> [FileEntry] in
            let ordered = group.sorted { $0.url.path < $1.url.path }
            return ordered.map { item in var item = item; item.groupID = "name:\(ordered[0].id)"; return item }
        }.sorted { (left: [FileEntry], right: [FileEntry]) in left[0].name.localizedStandardCompare(right[0].name) == .orderedAscending }
        let photoSeries = cancelled() || !options.findPhotoSeries ? [] : makePhotoSeries(files, interval: max(0, options.photoSeriesInterval), cancelled: cancelled)
        return ScanResult(files: files.sorted { $0.size == $1.size ? $0.id < $1.id : $0.size > $1.size },
                          duplicateGroups: duplicates.sorted { $0[0].id < $1[0].id },
                          sameNameGroups: sameNames, photoSeriesGroups: photoSeries,
                          issues: issues, scannedCount: scannedCount)
    }

    private func isScreenshot(_ url: URL) -> Bool {
        if let metadata = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
           let value = MDItemCopyAttribute(metadata, "kMDItemIsScreenCapture" as CFString) as? Bool, value { return true }
        // Filename matching is an explicit heuristic when Spotlight has no flag.
        let name = url.lastPathComponent.lowercased()
        return imageExtensions.contains(url.pathExtension.lowercased()) &&
            (name.hasPrefix("screenshot") || name.hasPrefix("screen shot") || name.hasPrefix("schermata") || name.hasPrefix("istantanea schermo"))
    }

    func verifiedDigest(_ file: FileEntry, cancelled: () -> Bool = { false }) throws -> String? {
        try hash(file, cancelled: cancelled)
    }

    private func hash(_ file: FileEntry, cancelled: () -> Bool) throws -> String? {
        var current = stat()
        guard lstat(file.url.path, &current) == 0, current.st_mode & S_IFMT == S_IFREG,
              current.st_flags & UInt32(SF_DATALESS) == 0,
              file.url.resolvingSymlinksInPath().path == file.url.standardizedFileURL.path,
              file.snapshotDevice == UInt64(UInt32(bitPattern: current.st_dev)),
              file.snapshotInode == UInt64(current.st_ino),
              current.st_size == file.size,
              abs(modificationDate(current).timeIntervalSince(file.modified)) < 0.000_001 else { throw ScannerError.changed }
        // Walk directory descriptors with openat/O_NOFOLLOW. Unlike resolving
        // a string first, this cannot follow an ancestor swapped to a symlink.
        // O_NOFOLLOW_ANY is unavailable on some otherwise supported kernels.
        let descriptor = openWithoutSymlinks(file.url)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_size == file.size, before.st_ino == current.st_ino,
              before.st_dev == current.st_dev, before.st_flags & UInt32(SF_DATALESS) == 0,
              before.st_mtimespec.tv_sec == current.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == current.st_mtimespec.tv_nsec else { throw ScannerError.changed }
        var hasher = SHA256()
        while true {
            if cancelled() { return nil }
            guard let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        var after = stat()
        var namedAfter = stat()
        guard fstat(descriptor, &after) == 0, before.st_size == after.st_size,
              before.st_ino == after.st_ino, before.st_dev == after.st_dev,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              lstat(file.url.path, &namedAfter) == 0,
              namedAfter.st_mode & S_IFMT == S_IFREG,
              namedAfter.st_ino == after.st_ino, namedAfter.st_dev == after.st_dev,
              namedAfter.st_size == after.st_size,
              namedAfter.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              namedAfter.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              file.url.resolvingSymlinksInPath().path == file.url.standardizedFileURL.path else { throw ScannerError.changed }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func modificationDate(_ value: stat) -> Date {
        Date(timeIntervalSince1970: Double(value.st_mtimespec.tv_sec) + Double(value.st_mtimespec.tv_nsec) / 1_000_000_000)
    }

    private func openWithoutSymlinks(_ url: URL) -> Int32 {
        let components = url.standardizedFileURL.pathComponents.filter { $0 != "/" }
        guard !components.isEmpty else { errno = EISDIR; return -1 }
        var directory = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { return -1 }
        for component in components.dropLast() {
            let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let failure = errno
            Darwin.close(directory)
            guard next >= 0 else { errno = failure; return -1 }
            directory = next
        }
        let file = openat(directory, components.last!, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        let failure = errno
        Darwin.close(directory)
        errno = failure
        return file
    }

    private func makePhotoSeries(_ files: [FileEntry], interval: TimeInterval, cancelled: () -> Bool) -> [[FileEntry]] {
        // Recovered PhotoSessionsModel path: one date-sorted input collection,
        // adjacent gaps strictly below 60 seconds; no parent-folder partition.
        // Evidence: ev_da5568e284f6250606e006a62c336aba8f32116da7ccb68ceb32f87a04c3bb21
        // and ev_a67ea1610ceef9954016e50316ba0d9fb788527991eaefa3bc1d91efc8f49ade.
        var series: [[FileEntry]] = []
        var dated: [(FileEntry, Date)] = []
        for file in files where imageExtensions.contains(file.url.pathExtension.lowercased()) {
            if cancelled() { return series }
            if let date = captureDate(file) { dated.append((file, date)) }
        }
        dated.sort { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }
        var group: [(FileEntry, Date)] = []
        var last: Date?
        func finish() {
            if group.count > 1, let first = group.first {
                // The inspected original rejects groups whose entries all have
                // identical logical sizes and capture dates (not a hash test).
                let identicalAttributes = group.allSatisfy { $0.0.size == first.0.size && $0.1 == first.1 }
                if !identicalAttributes {
                    let id = "series:\(first.0.id)"
                    series.append(group.map { entry in var file = entry.0; file.groupID = id; file.photoDate = entry.1; return file })
                }
            }
            group = []
        }
        for (file, date) in dated {
            if cancelled() { return series }
            if let previous = last, previous.timeIntervalSince(date) >= interval { finish() }
            group.append((file, date))
            last = date
        }
        finish()
        return series.sorted { $0[0].id < $1[0].id }
    }

    private func captureDate(_ file: FileEntry) -> Date? {
        // No filesystem-date fallback. The original also tries an ISOBMFF
        // parser after ExifParcer; that fallback is not implemented here, so
        // HEIC/container-only capture metadata can remain ungrouped.
        let descriptor = openWithoutSymlinks(file.url)
        guard descriptor >= 0 else { return nil }
        var state = stat()
        guard fstat(descriptor, &state) == 0, state.st_mode & S_IFMT == S_IFREG,
              state.st_flags & UInt32(SF_DATALESS) == 0, state.st_size == file.size,
              file.snapshotDevice == UInt64(UInt32(bitPattern: state.st_dev)),
              file.snapshotInode == UInt64(state.st_ino),
              abs(modificationDate(state).timeIntervalSince(file.modified)) < 0.000_001 else {
            Darwin.close(descriptor)
            return nil
        }
        // ImageIO reads through the verified descriptor, not a reopened URL.
        let storage = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        storage.initialize(to: descriptor)
        var callbacks = CGDataProviderDirectCallbacks(version: 0, getBytePointer: nil, releaseBytePointer: nil,
            getBytesAtPosition: { info, buffer, position, count in
                guard let info else { return 0 }
                let descriptor = info.assumingMemoryBound(to: Int32.self).pointee
                return max(0, pread(descriptor, buffer, count, position))
            }, releaseInfo: { info in
                guard let info else { return }
                let storage = info.assumingMemoryBound(to: Int32.self)
                Darwin.close(storage.pointee)
                storage.deinitialize(count: 1)
                storage.deallocate()
            })
        guard let provider = CGDataProvider(directInfo: storage, size: off_t(file.size), callbacks: &callbacks) else {
            Darwin.close(descriptor)
            storage.deinitialize(count: 1)
            storage.deallocate()
            return nil
        }
        defer { withExtendedLifetime(provider) {} }
        guard let source = CGImageSourceCreateWithDataProvider(provider, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        var after = stat()
        var namedAfter = stat()
        guard fstat(descriptor, &after) == 0, lstat(file.url.path, &namedAfter) == 0,
              after.st_ino == state.st_ino, after.st_dev == state.st_dev,
              after.st_size == state.st_size, after.st_mtimespec.tv_sec == state.st_mtimespec.tv_sec,
              after.st_mtimespec.tv_nsec == state.st_mtimespec.tv_nsec,
              namedAfter.st_ino == after.st_ino, namedAfter.st_dev == after.st_dev,
              file.url.resolvingSymlinksInPath().path == file.url.standardizedFileURL.path else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: original)
    }
}

private enum ScannerError: LocalizedError {
    case changed
    var errorDescription: String? { "Il file è cambiato durante il confronto; ripetere la scansione." }
}
