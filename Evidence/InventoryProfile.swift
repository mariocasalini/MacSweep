import Foundation
import CryptoKit
@main struct RealScanProfile {
 static func main() throws {
  let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/local.macsweep.desktop.plist")
  let d = try PropertyListSerialization.propertyList(from: Data(contentsOf:url), format:nil) as! [String:Any]
  let roots = ((d["roots"] as? [String] ?? []) + (d["downloadRoots"] as? [String] ?? [])).map { URL(fileURLWithPath:$0) }
  let excluded = (d["exclusions"] as? [String] ?? []).map { URL(fileURLWithPath:$0) }
  let begin = Date()
  let result = Scanner().scan(options: ScanOptions(roots:roots,exclusions:excluded + [URL(fileURLWithPath:"/Users/mariolone/Documents/Codex"), URL(fileURLWithPath:"/Users/mariolone/Documents/progettiPersonali/MacSweep")],findDuplicates:false,findSameNames:false,findPhotoSeries:false), cancelled: { Date().timeIntervalSince(begin) > 120 })
  let digest = SHA256.hash(data: Data(result.files.sorted { $0.id < $1.id }.map { "\($0.id)|\($0.size)" }.joined(separator:"\n").utf8)).map { String(format:"%02x",$0) }.joined()
  print("Inventory fingerprint: " + digest)
  print(String(format:"Inventory elapsed %.3f s; files %d; issues %d; bounded to 120 seconds",Date().timeIntervalSince(begin),result.scannedCount,result.issues.count))
 }
}
