import Foundation
import Darwin
import ImageIO
import CoreGraphics

@main
struct ScannerTests {
    static var assertionCount = 0
    static func main() throws {
        let manager = FileManager.default
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("work/scanner-fixture-\(UUID().uuidString)")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let a = root.appendingPathComponent("A")
        let b = root.appendingPathComponent("B")
        let skipped = root.appendingPathComponent("Skip")
        for directory in [a, b, skipped] { try manager.createDirectory(at: directory, withIntermediateDirectories: true) }
        let bytes = Data(repeating: 0x41, count: 40_000)
        try bytes.write(to: a.appendingPathComponent("original.dat"))
        try bytes.write(to: b.appendingPathComponent("copy.dat"))
        try Data(repeating: 0x42, count: 40_000).write(to: a.appendingPathComponent("same.dat"))
        try Data(repeating: 0x43, count: 40_000).write(to: b.appendingPathComponent("same.dat"))
        try bytes.write(to: skipped.appendingPathComponent("ignored.dat"))
        try Data("small".utf8).write(to: a.appendingPathComponent("small.dat"))
        try Data("small".utf8).write(to: b.appendingPathComponent("small.dat"))
        try manager.createSymbolicLink(at: root.appendingPathComponent("linked-file"), withDestinationURL: a.appendingPathComponent("original.dat"))
        try manager.createSymbolicLink(at: root.appendingPathComponent("linked-directory"), withDestinationURL: b)
        let app = root.appendingPathComponent("Example.app")
        try manager.createDirectory(at: app, withIntermediateDirectories: true)
        try bytes.write(to: app.appendingPathComponent("internal.dat"))
        let scanner = Scanner()
        var options = ScanOptions(roots: [root, a], exclusions: [skipped])
        let result = scanner.scan(options: options)
        expect(result.scannedCount == 6, "Selected roots overlap without double counting; excludes symlinks, packages, and skip folders: \(result.scannedCount), \(result.files.map(\.name)), \(result.issues)")
        expect(result.duplicateGroups.count == 1 && result.duplicateGroups[0].count == 2, "Only same bytes group as duplicates: \(result.issues)")
        expect(Set(result.duplicateGroups[0].map(\.name)) == Set(["original.dat", "copy.dat"]), "Name does not define duplicate content")
        expect(result.sameNameGroups.count == 1 && result.sameNameGroups[0][0].name == "same.dat", "Same names differ from duplicates; small entries skipped")
        expect(result.files.filter { $0.name == "small.dat" }.count == 2, "Small files remain in normal inventory")
        options.minDuplicateSize = 0
        let all = scanner.scan(options: options)
        expect(all.duplicateGroups.count == 2, "All-file mode compares small files")
        expect(all.sameNameGroups.count == 2, "All-file mode includes small same-name files")
        var inventoryOnly = options
        inventoryOnly.findDuplicates = false
        inventoryOnly.findSameNames = false
        inventoryOnly.findPhotoSeries = false
        let disabledAnalysis = scanner.scan(options: inventoryOnly)
        expect(disabledAnalysis.duplicateGroups.isEmpty, "Disabled duplicate analysis produces no comparison groups")
        expect(disabledAnalysis.sameNameGroups.isEmpty, "Disabled same-name analysis produces no groups")
        expect(disabledAnalysis.files.count == all.files.count, "Disabling content analysis preserves the shared read-only inventory")
        let cancelled = scanner.scan(options: options, cancelled: { true })
        expect(cancelled.scannedCount == 0 && cancelled.duplicateGroups.isEmpty, "Immediate cancellation stops traversal and hash work")
        var stopAfterInventory = false
        let noHashes = scanner.scan(options: options, cancelled: { stopAfterInventory }, progress: { _ in stopAfterInventory = true })
        expect(noHashes.scannedCount == 6 && noHashes.duplicateGroups.isEmpty, "Cancellation after inventory prevents hashing")
        let linked = scanner.scan(options: ScanOptions(roots: [root.appendingPathComponent("linked-directory")]))
        expect(linked.files.isEmpty && !linked.issues.isEmpty, "A symbolic root is rejected")
        let hidden = a.appendingPathComponent(".hidden.dat")
        try bytes.write(to: hidden)
        let recheck = scanner.scan(options: options)
        expect(!recheck.files.contains { $0.name == ".hidden.dat" }, "Hidden files are not included by default")
        expect(manager.fileExists(atPath: a.appendingPathComponent("original.dat").path), "Read-only scan preserves originals")
        var excludeFile = options
        excludeFile.exclusions.append(a.appendingPathComponent("original.dat"))
        let fileExcluded = scanner.scan(options: excludeFile)
        expect(fileExcluded.scannedCount == 5 && fileExcluded.files.contains { $0.name == "copy.dat" }, "Excluding a file does not skip a subsequent folder")
        expect(result.files.allSatisfy { $0.snapshotDevice != nil && $0.snapshotInode != nil }, "Every enumerated file captures filesystem identity")
        let originalURL = a.appendingPathComponent("original.dat")
        let originalEntry = result.files.first { $0.url == originalURL }!
        let savedDate = originalEntry.modified
        try bytes.write(to: originalURL, options: .atomic)
        try manager.setAttributes([.modificationDate: savedDate], ofItemAtPath: originalURL.path)
        let replaced = scanner.scan(options: options)
        let replacedEntry = replaced.files.first { $0.url == originalURL }!
        expect(originalEntry.snapshotInode != replacedEntry.snapshotInode && originalEntry.snapshotDevice == replacedEntry.snapshotDevice,
               "Atomic same-size replacement is detected by inode even with preserved modification date")

        var replacedBeforeHash = false
        let replacedWhileScanning = scanner.scan(options: options, progress: { _ in
            guard !replacedBeforeHash else { return }
            replacedBeforeHash = true
            try! bytes.write(to: originalURL, options: .atomic)
            try! manager.setAttributes([.modificationDate: savedDate], ofItemAtPath: originalURL.path)
        })
        expect(!replacedWhileScanning.duplicateGroups.flatMap({ $0 }).contains { $0.url == originalURL } && !replacedWhileScanning.issues.isEmpty,
               "Hashing rejects an entry replaced after inventory")

        let race = root.appendingPathComponent("race")
        let alternate = root.appendingPathComponent("alternate")
        let retained = root.appendingPathComponent("retained")
        for directory in [race, alternate] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            for name in ["first.bin", "second.bin"] { try bytes.write(to: directory.appendingPathComponent(name)) }
        }
        var hashPhase = false
        var checks = 0
        var swappedAncestor = false
        let raced = scanner.scan(options: ScanOptions(roots: [race]), cancelled: {
            if hashPhase {
                checks += 1
                if checks == 3 {
                    try! manager.moveItem(at: race, to: retained)
                    try! manager.createSymbolicLink(at: race, withDestinationURL: alternate)
                    swappedAncestor = true
                }
            }
            return false
        }, progress: { _ in hashPhase = true })
        expect(swappedAncestor && raced.duplicateGroups.isEmpty && !raced.issues.isEmpty,
               "A directory swapped for a symlink while a file is hashed fails identity verification")
        try manager.removeItem(at: race)
        try manager.moveItem(at: retained, to: race)
        let photos = root.appendingPathComponent("photo-fixtures")
        let boundary = photos.appendingPathComponent("boundary")
        let chain = photos.appendingPathComponent("chain")
        let crossA = photos.appendingPathComponent("crossA")
        let crossB = photos.appendingPathComponent("crossB")
        let missing = photos.appendingPathComponent("missing")
        let equalAttributes = photos.appendingPathComponent("equal-attributes")
        for directory in [boundary, chain, crossA, crossB, missing, equalAttributes] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try jpeg(at: boundary.appendingPathComponent("zero.jpg"), capture: "2026:10:01 12:00:00")
        try jpeg(at: boundary.appendingPathComponent("sixty.jpg"), capture: "2026:10:01 12:01:00")
        expect(scanner.scan(options: ScanOptions(roots: [boundary])).photoSeriesGroups.isEmpty,
               "An exact 60-second capture gap splits groups")
        for (index, capture) in ["2026:10:01 12:00:00", "2026:10:01 12:00:30", "2026:10:01 12:01:00", "2026:10:01 12:01:30"].enumerated() {
            try jpeg(at: chain.appendingPathComponent("photo-\(index).jpg"), capture: capture)
        }
        let chainResult = scanner.scan(options: ScanOptions(roots: [chain]))
        expect(chainResult.photoSeriesGroups.count == 1 && chainResult.photoSeriesGroups[0].count == 4,
               "Consecutive 30-second gaps chain four photos spanning 90 seconds")
        expect(chainResult.photoSeriesGroups[0].map(\.name) == ["photo-3.jpg", "photo-2.jpg", "photo-1.jpg", "photo-0.jpg"],
               "Photo series preserve newest-first capture order")
        var narrower = ScanOptions(roots: [chain])
        narrower.photoSeriesInterval = 30
        expect(scanner.scan(options: narrower).photoSeriesGroups.isEmpty,
               "A custom interval also uses strict rather than inclusive comparison")
        try jpeg(at: crossA.appendingPathComponent("first.jpg"), capture: "2026:10:01 12:00:00")
        try jpeg(at: crossB.appendingPathComponent("second.jpg"), capture: "2026:10:01 12:00:30")
        let cross = scanner.scan(options: ScanOptions(roots: [crossA, crossB]))
        expect(cross.photoSeriesGroups.count == 1 && cross.photoSeriesGroups[0].count == 2,
               "Photos in distinct selected directories can belong to one temporal chain")
        try jpeg(at: missing.appendingPathComponent("known-zero.jpg"), capture: "2026:10:01 12:00:00")
        try jpeg(at: missing.appendingPathComponent("known-thirty.jpg"), capture: "2026:10:01 12:00:30")
        try jpeg(at: missing.appendingPathComponent("no-exif.jpg"), capture: nil)
        try jpeg(at: missing.appendingPathComponent("bad-exif.jpg"), capture: "not a capture date")
        let missingResult = scanner.scan(options: ScanOptions(roots: [missing]))
        expect(missingResult.files.count == 4 && missingResult.photoSeriesGroups.count == 1 &&
               Set(missingResult.photoSeriesGroups[0].map(\.name)) == Set(["known-zero.jpg", "known-thirty.jpg"]),
               "Missing or invalid EXIF dates remain inventoried but are excluded from photo series")
        let firstEqual = equalAttributes.appendingPathComponent("first.jpg")
        try jpeg(at: firstEqual, capture: "2026:10:01 12:00:00")
        try Data(contentsOf: firstEqual).write(to: equalAttributes.appendingPathComponent("copy.jpg"))
        let equalResult = scanner.scan(options: ScanOptions(roots: [equalAttributes], minDuplicateSize: 0))
        expect(equalResult.photoSeriesGroups.isEmpty && equalResult.duplicateGroups.count == 1,
               "Equal-size equal-capture-date groups are suppressed as photo series while duplicates remain detectable")
        let sampledRoot = root.appendingPathComponent("SampledComparison")
        try manager.createDirectory(at: sampledRoot, withIntermediateDirectories: true)
        let large = Data(repeating: 0x55, count: 1_048_576)
        try large.write(to: sampledRoot.appendingPathComponent("a.bin"))
        try large.write(to: sampledRoot.appendingPathComponent("b.bin"))
        var sameSamples = large
        sameSamples[100_000] = 0x99
        try sameSamples.write(to: sampledRoot.appendingPathComponent("different-between-samples.bin"))
        try Data(repeating: 0x66, count: large.count).write(to: sampledRoot.appendingPathComponent("different-sample.bin"))
        let sampled = scanner.scan(options: ScanOptions(roots: [sampledRoot]))
        expect(sampled.files.count == 4 && sampled.issues.isEmpty, "Sample prefilter preserves inventory")
        expect(sampled.duplicateGroups.count == 1 && Set(sampled.duplicateGroups[0].map(\.name)) == Set(["a.bin", "b.bin"]), "Sample collisions require full SHA-256; only exact content matches")
        var comparisonStarted = false
        var comparisonChecks = 0
        let stoppedSample = scanner.scan(options: ScanOptions(roots: [sampledRoot]), cancelled: {
            if comparisonStarted { comparisonChecks += 1 }
            return comparisonChecks > 4
        }, phase: { if $0 == "Confronto dei duplicati…" { comparisonStarted = true } })
        expect(stoppedSample.files.count == 4 && stoppedSample.duplicateGroups.isEmpty, "Cancellation during sampled comparison keeps inventory without incomplete groups")
        var earlyFiles: [FileEntry] = []
        var inventoryWasPublished = false
        var comparingAfterInventory = false
        let staged = scanner.scan(options: ScanOptions(roots: [sampledRoot]), phase: {
            if $0 == "Confronto dei duplicati…" { comparingAfterInventory = inventoryWasPublished }
        }, inventory: { earlyFiles = $0; inventoryWasPublished = true })
        expect(comparingAfterInventory && earlyFiles.map(\.id) == staged.files.map(\.id), "Inventory is published before content analysis with the same ordered files")
        let unicode = sampledRoot.appendingPathComponent("Cartella è 日本語")
        try manager.createDirectory(at: unicode, withIntermediateDirectories: true)
        try Data("unicode".utf8).write(to: unicode.appendingPathComponent("file è 日本語.txt"))
        let nested = scanner.scan(options: ScanOptions(roots: [sampledRoot]))
        expect(nested.files.count == 5 && nested.files.contains { $0.name == "file è 日本語.txt" }, "Descriptor traversal preserves nested Unicode filenames")
        print("Scanner: \(assertionCount) fixture checks passed")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertionCount += 1
        guard condition() else { fatalError("FAIL: \(message)") }
    }

    /// Creates an actual JPEG and embeds the capture timestamp through ImageIO.
    static func jpeg(at url: URL, capture: String?) throws {
        guard let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw NSError(domain: "ScannerTests", code: 1)
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        guard let image = context.makeImage() else { throw NSError(domain: "ScannerTests", code: 2) }
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        if let capture { properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: capture] }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "ScannerTests", code: 3) }
    }
}
