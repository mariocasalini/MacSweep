import Foundation
@main struct SidebarChecks {
 @MainActor static func main() {
  let m = Model()
  assert(m.sidebarSpace(for: .duplicates) == "—")
  m.busy = true
  assert(m.sidebarSpace(for: .duplicates) == "…")
  m.busy = false; m.hasScanned = true
  func file(_ name: String) -> FileEntry { FileEntry(id: name, url: URL(fileURLWithPath: "/tmp/" + name), name: name, size: 2_000_000, modified: Date(), created: Date(), category: "other") }
  let copies = [file("a"), file("b"), file("c")]
  m.result.files = copies; m.result.duplicateGroups = [copies]
  assert(m.sidebarSpace(for: .duplicates) == "4 MB")
  assert(m.sidebarSpace(for: .largest) == "6 MB")
  m.query = "does-not-match"; m.selected = ["a"]
  assert(m.sidebarSpace(for: .duplicates) == "4 MB")
  assert(m.sidebarSpace(for: .downloads) == "0 MB")
  assert(m.sidebarSpace(for: .caches) == "—")
  m.didScanJunk = true
  assert(m.sidebarSpace(for: .caches) == "0 MB")
  m.enabledCategories.remove(Section.duplicates.rawValue)
  assert(m.sidebarSpace(for: .duplicates) == "Off")
  assert(m.sidebarSpace(for: .settings) == nil)
  print("PASS 10 sidebar space checks")
 }
}
