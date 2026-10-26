import Foundation
import Darwin

@main
struct JunkScannerTests {
    static func main() throws {
        let fm = FileManager.default
        // An isolated generated fake home, never the real user's Library.
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixture = project.appendingPathComponent("work/junk-fixture-\(UUID())")
        let home = fixture.appendingPathComponent("home")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: fixture) }
        @discardableResult func file(_ relative: String) throws -> URL {
            let url = home.appendingPathComponent(relative)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture:\(relative)".utf8).write(to: url)
            return url
        }
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name); print("PASS \(name)")
        }
        let ordinary = try file("Library/Caches/com.example.utility/a.bin")
        let sibling = try file("Library/Caches/com.example.utility/b.bin")
        let excludedDirectoryFile = try file("Library/Caches/excluded/sub/c.bin")
        let logs = try file("Library/Logs/com.example.utility/app.log")
        let browser = try file("Library/Caches/Google/Chrome/Default/browser.bin")
        let containerCache = try file("Library/Containers/com.example.utility/Data/Library/Caches/c.bin")
        let containerLog = try file("Library/Containers/com.example.utility/Data/Library/Logs/app.log")
        let containerBrowser = try file("Library/Containers/com.apple.Safari/Data/Library/Caches/WebKit/cache.bin")
        let appSuffixCache = try file("Library/Containers/com.example.app/Data/Library/Caches/cache.bin")
        let appSuffixContents = try file("Library/Containers/com.example.app/Contents/Resources/untouched.bin")
        let document = try file("Library/Containers/com.example.utility/Data/Documents/important.txt")
        let preference = try file("Library/Containers/com.example.utility/Data/Library/Preferences/com.example.utility.plist")
        let localStorage = try file("Library/Containers/com.example.utility/Data/Library/WebKit/LocalStorage/db.sqlite")
        let shared = try file("Library/Group Containers/group.example/Library/Caches/shared.bin")
        let outside = try file("unrelated/outside.bin")
        let symlink = home.appendingPathComponent("Library/Caches/symlink.bin")
        try fm.createSymbolicLink(at: symlink, withDestinationURL: outside)
        let containerLink = home.appendingPathComponent("Library/Containers/com.link.app")
        try fm.createSymbolicLink(at: containerLink, withDestinationURL: home.appendingPathComponent("Library/Containers/com.example.utility"))
        let package = try file("Library/Caches/Test.app/Contents/test.bin")
        let noContainers = JunkScanner.scan(exclusions: [], home: home, cancelled: { false })
        let defaultPaths = Set(noContainers.0.map(\.id))
        check(defaultPaths.contains(ordinary.path) && defaultPaths.contains(logs.path), "default user cache/log roots")
        check(!defaultPaths.contains(containerCache.path) && !defaultPaths.contains(containerLog.path), "containers excluded by default")
        check(noContainers.0.first(where: { $0.id == browser.path })?.category == "browsers", "known browser cache classification")
        check(!defaultPaths.contains(symlink.path) && !defaultPaths.contains(package.path), "symlinks and packages ignored")
        let enabled = JunkScanner.scan(exclusions: [], includeContainers: true, home: home, cancelled: { false })
        let enabledPaths = Set(enabled.0.map(\.id))
        check(enabledPaths.contains(containerCache.path) && enabledPaths.contains(containerLog.path), "opt-in exact container cache/log suffixes")
        check(enabledPaths.contains(appSuffixCache.path), "container bundle ID ending app is admitted")
        check(!enabledPaths.contains(appSuffixContents.path) && fm.fileExists(atPath: appSuffixContents.path), "app-suffix container contents outside exact roots untouched")
        check(enabled.0.first(where: { $0.id == containerBrowser.path })?.category == "browsers", "container browser bundle classification")
        check([document, preference, localStorage, shared, outside].allSatisfy { !enabledPaths.contains($0.path) }, "documents preferences localstorage shared and unrelated data excluded")
        check(!enabledPaths.contains(where: { $0.contains("/com.link.app/") }), "symlink container ignored")
        let excluded = JunkScanner.scan(exclusions: [ordinary, excludedDirectoryFile.deletingLastPathComponent().deletingLastPathComponent(), home.appendingPathComponent("Library/Containers/com.example.utility/Data/Library/Logs")], includeContainers: true, home: home, cancelled: { false })
        let excludedPaths = Set(excluded.0.map(\.id))
        check(!excludedPaths.contains(ordinary.path) && excludedPaths.contains(sibling.path), "excluded file does not skip sibling")
        check(!excludedPaths.contains(excludedDirectoryFile.path) && !excludedPaths.contains(containerLog.path), "directory and container-root exclusions")
        let rootExcluded = JunkScanner.scan(exclusions: [home.appendingPathComponent("Library/Caches")], home: home, cancelled: { false })
        check(rootExcluded.0.map(\.id) == [logs.path], "whole-root exclusion preserves other root")
        let cancelled = JunkScanner.scan(exclusions: [], includeContainers: true, home: home, cancelled: { true })
        check(cancelled.0.isEmpty, "prestart cancellation")
        var checks = 0
        let partial = JunkScanner.scan(exclusions: [], includeContainers: true, home: home, cancelled: { checks += 1; return checks >= 8 })
        check(partial.0.count < enabled.0.count, "mid-inventory cancellation returns bounded partial result")
        check(enabled.0.allSatisfy { $0.snapshotDevice != nil && $0.snapshotInode != nil }, "device/inode snapshots populated")
        if let entry = enabled.0.first(where: { $0.id == ordinary.path }) {
            var state = stat(); check(lstat(ordinary.path, &state) == 0, "fixture stat available")
            let expected = Double(state.st_mtimespec.tv_sec) + Double(state.st_mtimespec.tv_nsec) / 1_000_000_000
            check(abs(entry.modified.timeIntervalSince1970 - expected) < 0.000_001 && entry.size == state.st_size, "snapshot size and stat mtime match")
        }
        let missingHome = fixture.appendingPathComponent("missing-home")
        let missing = JunkScanner.scan(exclusions: [], includeContainers: true, home: missingHome, cancelled: { false })
        check(missing.0.isEmpty && missing.1.isEmpty, "missing roots are not errors")
        check([document, preference, localStorage, shared, outside].allSatisfy { fm.fileExists(atPath: $0.path) }, "all excluded fixture data remains untouched")
        let supportGPU = try file("Library/Application Support/Google/Chrome/Default/GPUCache/cache.bin")
        let supportScript = try file("Library/Application Support/Google/Chrome/Default/Service Worker/ScriptCache/code.bin")
        let supportStorage = try file("Library/Application Support/Google/Chrome/Profile 1/Service Worker/CacheStorage/site/cache.bin")
        let cookies = try file("Library/Application Support/Google/Chrome/Default/Cookies")
        let browserHistory = try file("Library/Application Support/Google/Chrome/Default/History")
        let websiteStorage = try file("Library/Application Support/Google/Chrome/Default/Local Storage/site.db")
        let login = try file("Library/Application Support/Google/Chrome/Default/Login Data")
        let arbitrary = try file("Library/Application Support/Unrelated/GPUCache/cache.bin")
        let chromeScan = JunkScanner.scan(exclusions: [], home: home, cancelled: { false })
        let chromeIDs = Set(chromeScan.0.map(\.id))
        check([supportGPU,supportScript,supportStorage].allSatisfy { chromeIDs.contains($0.path) }, "verified Chrome profile cache suffixes included")
        check(chromeScan.0.filter { [supportGPU,supportScript,supportStorage].contains($0.url) }.allSatisfy { $0.category == "browsers" }, "Application Support caches classified as browser cache")
        check([cookies,browserHistory,websiteStorage,login,arbitrary].allSatisfy { !chromeIDs.contains($0.path) && fm.fileExists(atPath:$0.path) }, "cookies history logins local storage and unrelated support data excluded")
        check(chromeIDs.count == chromeScan.0.count, "browser roots do not duplicate files")
        let omitChrome = JunkScanner.scan(exclusions:[home.appendingPathComponent("Library/Application Support/Google/Chrome")],home:home,cancelled:{false})
        check(!omitChrome.0.contains { [supportGPU,supportScript,supportStorage].contains($0.url) }, "Chrome support root exclusion honored")
        let spotify = try file("Library/Caches/com.spotify.client/Storage/offline.bin")
        let maps = try file("Library/Caches/GeoServices/maps.bin")
        let retained = JunkScanner.scan(exclusions:[],home:home,cancelled:{false})
        check(!retained.0.contains { $0.url == spotify || $0.url == maps }, "Spotify media and map stores excluded from standard cleanup")
        check(fm.fileExists(atPath:spotify.path) && fm.fileExists(atPath:maps.path), "retained media and maps untouched")
        print("Junk scanner tests complete; only generated fake-home fixtures were read.")
    }
}
