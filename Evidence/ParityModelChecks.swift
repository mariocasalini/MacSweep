import Foundation
@main struct ParityModelChecks {
 @MainActor static func main() {
  let m=Model(); m.enabledCategories=Set(Section.allCases.map(\.rawValue))
  precondition(m.includeJunk)
  func file(_ id:String,_ category:String,_ size:Int64)->FileEntry { FileEntry(id:id,url:URL(fileURLWithPath:id),name:"fixture",size:size,modified:Date(),created:Date(),category:category) }
  m.junk=[file("/fixture/cache","caches",2_000_000),file("/fixture/browser","browsers",3_000_000),file("/fixture/log","logs",1000)]
  m.didScanJunk=true; m.hasScanned=false
  precondition(m.sidebarSpace(for:.caches)=="2 MB" && m.sidebarSpace(for:.browsers)=="3 MB")
  precondition(m.files(for:.junk).count==3)
  m.reviewJunk([.browsers])
  precondition(m.section == .junk && m.pending.map(\.path)==["/fixture/browser"] && m.showRemoval)
  m.showRemoval=false; m.busy=true; m.reviewJunk([.caches]); precondition(!m.showRemoval)
  m.busy=false; m.enabledCategories.remove("browsers"); m.selected=[]
  precondition(m.files(for:.junk).count==2)
  m.reviewJunk([.browsers]); precondition(m.selected.isEmpty && !m.showRemoval)
  m.didScanJunk=false; precondition(m.sidebarSpace(for:.caches)=="—")
  print("PASS cache-only badges, aggregate scope, reviewed categories, busy guard, disabled categories and unknown state")
 }
}
