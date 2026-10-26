import Foundation

@main
@MainActor
struct SafetyTests {
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixture-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let allowed = root.appendingPathComponent("allowed"), sibling = root.appendingPathComponent("allowed-other")
        try fm.createDirectory(at: allowed, withIntermediateDirectories: true)
        try fm.createDirectory(at: sibling, withIntermediateDirectories: true)
        let file = allowed.appendingPathComponent("sample.txt"), outside = sibling.appendingPathComponent("outside.txt")
        try Data("fixture".utf8).write(to: file)
        try Data("fixture".utf8).write(to: outside)
        func check(_ condition: @autoclosure () -> Bool, _ name: String) { precondition(condition(), name); print("PASS \(name)") }
        check(RemovalStore.validationError(url: file, allowedRoots: [allowed]) == nil, "authorized descendant")
        check(RemovalStore.validationError(url: allowed, allowedRoots: [allowed]) != nil, "reject scan root itself")
        check(RemovalStore.validationError(url: outside, allowedRoots: [allowed]) != nil, "path boundary rejects sibling prefix")
        check(RemovalStore.validationError(url: root, allowedRoots: [allowed], exactAllowed: [root]) != nil, "reject parent containing scan root")
        check(RemovalStore.validationError(url: URL(fileURLWithPath: "/System/Library"), allowedRoots: [URL(fileURLWithPath: "/")], exactAllowed: [URL(fileURLWithPath: "/System/Library")]) != nil, "system protection cannot be overridden")
        let link = allowed.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        check(RemovalStore.validationError(url: link, allowedRoots: [allowed], exactAllowed: [link]) != nil, "reject symbolic link")
        let dirLink = root.appendingPathComponent("directory-link")
        try fm.createSymbolicLink(at: dirLink, withDestinationURL: allowed)
        check(RemovalStore.validationError(url: dirLink.appendingPathComponent("sample.txt"), allowedRoots: [dirLink]) != nil, "reject symlink ancestor")
        check(RemovalStore.validationError(url: outside, allowedRoots: [], exactAllowed: [outside]) == nil, "explicit individual artifact")
        let cacheRoot = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        check(RemovalStore.validationError(url: cacheRoot, allowedRoots: [], exactAllowed: [cacheRoot]) != nil, "cache root is always protected")
        let groupContainer = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Group Containers/example")
        check(RemovalStore.validationError(url: groupContainer, allowedRoots: [], exactAllowed: [groupContainer]) != nil, "shared group container is protected")
        let journal = root.appendingPathComponent("corrupt.json")
        try Data("not-json".utf8).write(to: journal)
        let store = RemovalStore(storageURL: journal)
        check(store.loadError != nil, "corrupt history fails closed")
        check(!store.trash(urls: [file], allowedRoots: [allowed]).isEmpty, "no deletion with corrupt history")
        check(fm.fileExists(atPath: file.path), "file survives rejected operation")
        let batch = root.appendingPathComponent("batch")
        let fakeTrash = root.appendingPathComponent("fake-trash")
        try fm.createDirectory(at: batch, withIntermediateDirectories: true)
        try fm.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
        let paths = (0..<200).map { batch.appendingPathComponent("tiny-\($0).txt") }
        for path in paths { try Data("small".utf8).write(to: path) }
        let storage = root.appendingPathComponent("batch-history.json")
        let legacy = RemovalRecord(id: UUID(), originalPath: "/fixture/legacy", trashedPath: nil, date: Date(), restored: false, error: "fixture", identity: nil)
        let legacyBytes = try JSONEncoder().encode([legacy])
        try legacyBytes.write(to: storage)
        var moves = 0
        let batching = RemovalStore(storageURL: storage, trashOperation: { source in
            moves += 1
            let dest = fakeTrash.appendingPathComponent(source.lastPathComponent)
            try fm.moveItem(at: source, to: dest)
            return dest
        })
        let failures = batching.trash(urls: paths, allowedRoots: [batch])
        check(failures.isEmpty && moves == paths.count, "200 tiny fixture files move exactly once")
        check(batching.records.count == 201 && batching.records.dropFirst().allSatisfy { $0.trashedPath != nil && $0.identity != nil }, "every move has destination and identity")
        check(try! Data(contentsOf: storage) == legacyBytes, "legacy history is preserved byte-for-byte")
        let reloaded = RemovalStore(storageURL: storage)
        check(reloaded.loadError == nil && reloaded.records.count == 201, "legacy plus append journal reload without duplicated records")
        check(reloaded.records.dropFirst().allSatisfy { $0.error == nil }, "completed events supersede intent events")
        let first = reloaded.records[1]
        try Data("occupant".utf8).write(to: URL(fileURLWithPath: first.originalPath))
        check(reloaded.restore(first.id) != nil, "restore refuses occupied original path")
        try fm.removeItem(atPath: first.originalPath)
        check(reloaded.restore(first.id) == nil && fm.fileExists(atPath: first.originalPath), "restoration succeeds from replayed journal")
        let restored = RemovalStore(storageURL: storage)
        check(restored.records[1].restored, "restore completion survives reload")
        let events = RemovalJournal.eventsURL(for: storage)
        check((try! fm.attributesOfItem(atPath: events.path)[.posixPermissions] as! NSNumber).intValue == 0o600, "journal permissions are private")
        let torn = root.appendingPathComponent("torn.json")
        try Data("incomplete".utf8).write(to: RemovalJournal.eventsURL(for: torn))
        check(RemovalStore(storageURL: torn).loadError != nil, "torn append fails closed")
        let linkJournal = root.appendingPathComponent("linked.json")
        try fm.createSymbolicLink(at: RemovalJournal.eventsURL(for: linkJournal), withDestinationURL: events)
        check(RemovalStore(storageURL: linkJournal).loadError != nil, "symlink journal is rejected")
        let badParent = root.appendingPathComponent("not-a-directory")
        try Data("block".utf8).write(to: badParent)
        var unexpectedMove = false
        let unwritable = RemovalStore(storageURL: badParent.appendingPathComponent("history.json"), trashOperation: { _ in unexpectedMove = true; return nil })
        check(!unwritable.trash(urls: [file], allowedRoots: [allowed]).isEmpty && !unexpectedMove && fm.fileExists(atPath: file.path), "failed intent persistence never invokes move")
        print("Safety tests complete; no real files were moved to Trash.")
    }
}
