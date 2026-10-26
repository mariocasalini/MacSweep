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
        print("Safety tests complete; no real files were moved to Trash.")
    }
}
