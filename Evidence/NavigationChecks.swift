import Foundation
@main struct NavigationChecks {
 @MainActor static func main() {
  let m = Model()
  let now = Date()
  let entries = (0..<80_000).map { i in FileEntry(id: "\(i)", url: URL(fileURLWithPath: "/fixture/Downloads/\(i).dat"), name: "file-\(i)", size: Int64(i + 1), modified: now, created: now, category: i % 2 == 0 ? "installers" : "screenshots") }
  m.result.files = entries
  m.result.duplicateGroups = stride(from: 0, to: 3000, by: 3).map { Array(entries[$0..<$0+3]) }
  m.hasScanned = true
  let start = Date()
  var checksum = 0
  for _ in 0..<3 {
   for section in [Section.largest, .downloads, .installers, .screenshots, .duplicates] {
    m.open(section)
    for _ in 0..<6 {
     checksum += m.filtered.count + m.visible.count + m.selectedFiles.count
     for c in [Section.largest, .downloads, .installers, .screenshots, .duplicates] { checksum += m.sidebarSpace(for: c)?.count ?? 0 }
    }
   }
  }
  print(String(format: "Navigation: %.4f seconds; checksum %d",Date().timeIntervalSince(start),checksum))
  m.open(.largest); assert(m.filtered.first?.size == 80000)
  m.sort = "sizeUp"; assert(m.filtered.first?.size == 1)
  m.query = "file-79999"; assert(m.filtered.count == 1)
  m.query = ""; m.sort = "selected"; m.selected = ["99"]; assert(m.filtered.first?.id == "99" && m.selectedFiles.count == 1)
  m.selected = ["98"]; assert(m.filtered.first?.id == "98" && m.selectedFiles.first?.id == "98")
  m.result.files.removeAll { $0.id == "98" }; assert(m.selectedFiles.isEmpty && m.filtered.count == 79999)
  m.open(.installers); assert(m.files(for: .installers).count == 39999)
  m.enabledCategories.remove(Section.installers.rawValue); assert(m.files(for: .installers).isEmpty && m.filtered.isEmpty && m.sidebarSpace(for: .installers) == "Off")
  m.enabledCategories.insert(Section.installers.rawValue); assert(m.files(for: .installers).count == 39999)
  m.result.files = []; m.result.duplicateGroups = []; assert(m.files(for: .downloads).isEmpty && m.sidebarSpace(for: .duplicates) == "0 MB")
  m.junk = [entries[0]]; m.junk[0].category = "caches"; m.didScanJunk = true
  assert(m.files(for: .caches).count == 1 && m.sidebarSpace(for: .caches) == "<1 MB")
  m.junk = []; assert(m.files(for: .caches).isEmpty && m.sidebarSpace(for: .caches) == "0 MB")
  m.result.files = [FileEntry(id:"custom", url:URL(fileURLWithPath:"/custom/a"),name:"a",size:2,modified:now,created:now,category:"largest")]
  assert(m.files(for: .downloads).isEmpty)
  m.downloadRoots = [URL(fileURLWithPath:"/custom")]; assert(m.files(for: .downloads).count == 1)
  print("PASS navigation cache invalidation, search, sorting, selection, removal, categories, junk, download roots")
 }
}
